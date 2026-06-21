open Repr.Value
open Repr.Header
open Bigarray

type chunk = {
  data : memory;
  base_address : int;
  size : int;
  mutex : Mutex.t;
  mutable free_list : int64;
}

type root = { values : word array; next : root option }

type major_heap = {
  chunks : chunk array Atomic.t;
  chunks_lock : Mutex.t;
  chunk_size : int;
  base_offset : int;
  mutable major_collections : int;
  next_chunk_hint : int Atomic.t;
  mark_queue : int Queue.t;
}

type minor_heap = {
  domain_id : int;
  minor : memory;
  minor_size : int;
  mutable young_ptr : int;
  mutable roots : root option;
  mutable promoted_words : int;
  mutable minor_collections : int;
  rem_set : (int, unit) Hashtbl.t;
  mutable local_chunk : int;
  major : major_heap;
}

let free_list_nil = -1L
let min_free_words = 2

let create_major ~chunk_size ~base_offset =
  {
    chunks = Atomic.make [||];
    chunks_lock = Mutex.create ();
    chunk_size;
    base_offset;
    major_collections = 0;
    next_chunk_hint = Atomic.make 0;
    mark_queue = Queue.create ();
  }

let create_minor ~domain_id ~minor_size ~major =
  {
    domain_id;
    minor = create_memory minor_size;
    minor_size;
    young_ptr = minor_size;
    roots = None;
    promoted_words = 0;
    minor_collections = 0;
    rem_set = Hashtbl.create 64;
    local_chunk = -1;
    major;
  }

let[@inline] get_next (chunk : chunk) (block_ptr : int64) : int64 =
  chunk.data.{Int64.to_int block_ptr - chunk.base_address}

let[@inline] set_next (chunk : chunk) (block_ptr : int64) (next : int64) : unit
    =
  chunk.data.{Int64.to_int block_ptr - chunk.base_address} <- next

let create_chunk ~index ~chunk_size ~base_offset : chunk =
  let data = create_memory chunk_size in
  Array1.fill data 0L;
  let base_address = base_offset + (index * chunk_size) in
  data.{0} <- make ~size:(chunk_size - 1) ~color:color_blue ~tag:0;
  let chunk =
    {
      data;
      base_address;
      size = chunk_size;
      mutex = Mutex.create ();
      free_list = free_list_nil;
    }
  in
  let body_ptr = Int64.of_int (base_address + 1) in
  set_next chunk body_ptr free_list_nil;
  chunk.free_list <- body_ptr;
  chunk

let grow_major (major : major_heap) : int * chunk =
  Mutex.lock major.chunks_lock;
  Fun.protect
    ~finally:(fun () -> Mutex.unlock major.chunks_lock)
    (fun () ->
      let old = Atomic.get major.chunks in
      let index = Array.length old in
      let chunk =
        create_chunk ~index ~chunk_size:major.chunk_size
          ~base_offset:major.base_offset
      in
      Atomic.set major.chunks (Array.append old [| chunk |]);
      (index, chunk))

let chunk_index_of (major : major_heap) ptr =
  (ptr - major.base_offset) / major.chunk_size

let find_chunk (major : major_heap) (ptr : int) : chunk =
  let chunks = Atomic.get major.chunks in
  let idx = chunk_index_of major ptr in
  if idx < 0 || idx >= Array.length chunks then
    invalid_arg
      (Printf.sprintf "Heap.find_chunk: no chunk covers address %d" ptr)
  else chunks.(idx)

let alloc_chunk (chunk : chunk) ~size ~tag : word option =
  Mutex.lock chunk.mutex;
  Fun.protect
    ~finally:(fun () -> Mutex.unlock chunk.mutex)
    (fun () ->
      let total = size + 1 in
      let rec go prev curr =
        if curr = free_list_nil then None
        else
          let local = Int64.to_int curr - chunk.base_address in
          let hdr = chunk.data.{local - 1} in
          let block_total = Repr.Header.size hdr + 1 in
          let next = get_next chunk curr in
          if block_total < total then go (Some curr) next
          else begin
            let remainder = block_total - total in
            if remainder < min_free_words then begin
              (match prev with
              | None -> chunk.free_list <- next
              | Some p -> set_next chunk p next);
              chunk.data.{local - 1} <-
                make ~size:(block_total - 1) ~color:color_white ~tag;
              Some (word_of_ptr curr)
            end
            else begin
              let rem_ptr = Int64.add curr (Int64.of_int total) in
              let rem_local = Int64.to_int rem_ptr - chunk.base_address in
              chunk.data.{rem_local - 1} <-
                make ~size:(remainder - 1) ~color:color_blue ~tag:0;
              set_next chunk rem_ptr next;
              (match prev with
              | None -> chunk.free_list <- rem_ptr
              | Some p -> set_next chunk p rem_ptr);
              chunk.data.{local - 1} <- make ~size ~color:color_white ~tag;
              Some (word_of_ptr curr)
            end
          end
      in
      go None chunk.free_list)

let alloc_major (d : minor_heap) ~size ~tag : word =
  let major = d.major in
  if size + 1 > major.chunk_size then
    invalid_arg
      "Heap.alloc_major: object larger than chunk_size (no large-object path \
       yet)";
  let chunks = Atomic.get major.chunks in
  let n = Array.length chunks in
  let from_local =
    if d.local_chunk >= 0 && d.local_chunk < n then
      alloc_chunk chunks.(d.local_chunk) ~size ~tag
    else None
  in
  match from_local with
  | Some w -> w
  | None -> (
      let start = Atomic.fetch_and_add major.next_chunk_hint 1 in
      let rec scan count =
        if count >= n then None
        else
          let i = (start + count) mod n in
          match alloc_chunk chunks.(i) ~size ~tag with
          | Some w ->
              d.local_chunk <- i;
              Some w
          | None -> scan (count + 1)
      in
      let from_scan = if n = 0 then None else scan 0 in
      match from_scan with
      | Some w -> w
      | None -> (
          let index, chunk = grow_major major in
          match alloc_chunk chunk ~size ~tag with
          | Some w ->
              d.local_chunk <- index;
              w
          | None -> assert false))

let read_field (major : major_heap) ptr i : word =
  let chunk = find_chunk major ptr in
  chunk.data.{ptr - chunk.base_address + i}

let write_field (major : major_heap) ptr i (w : word) =
  let chunk = find_chunk major ptr in
  chunk.data.{ptr - chunk.base_address + i} <- w

let alloc_minor_raw (d : minor_heap) ~size ~tag : word option =
  let total = size + 1 in
  if total > d.young_ptr then None
  else begin
    let new_ptr = d.young_ptr - total in
    d.minor.{new_ptr} <- make ~size ~color:color_white ~tag;
    d.young_ptr <- new_ptr;
    Some (word_of_ptr (Int64.of_int (new_ptr + 1)))
  end
