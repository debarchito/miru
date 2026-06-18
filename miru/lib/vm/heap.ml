open Memory.Value
open Memory.Header
open Bigarray

type chunk = {
  data : memory;
  base_address : int;
  size : int;
  mutable free_ptr : int;
  mutable free_words : int;
  cards : (int, int8_unsigned_elt, c_layout) Array1.t;
}

type root = { values : word array; next : root option }

type major_heap = {
  mutable chunks : chunk list;
  mutable next_base : int;
  chunk_size : int;
  card_size : int;
  mutable major_collections : int;
  mutex : Mutex.t;
  mutable mark_queue : int Queue.t;
}

type minor_heap = {
  minor : memory;
  minor_size : int;
  mutable young_ptr : int;
  mutable roots : root option;
  mutable promoted_words : int;
  mutable minor_collections : int;
  mutable rem_set : int list;
  major : major_heap;
}

let create_chunk ~base_address ~chunk_size ~card_size =
  {
    data = create_memory chunk_size;
    base_address;
    size = chunk_size;
    free_ptr = 0;
    free_words = chunk_size;
    cards = Array1.create int8_unsigned c_layout (chunk_size / card_size);
  }

let create_major ~chunk_size ~card_size =
  {
    chunks = [];
    next_base = 0;
    chunk_size;
    card_size;
    major_collections = 0;
    mutex = Mutex.create ();
    mark_queue = Queue.create ();
  }

let create_minor ~minor_size ~major =
  {
    minor = create_memory minor_size;
    minor_size;
    young_ptr = minor_size;
    roots = None;
    promoted_words = 0;
    minor_collections = 0;
    rem_set = [];
    major;
  }

let alloc_chunk (chunk : chunk) ~size ~tag : word option =
  let total = size + 1 in
  if chunk.free_words < total then None
  else begin
    let global_ptr = chunk.base_address + chunk.free_ptr + 1 in
    chunk.data.{chunk.free_ptr} <- make ~size ~color:color_white ~tag;
    chunk.free_ptr <- chunk.free_ptr + total;
    chunk.free_words <- chunk.free_words - total;
    Some (word_of_ptr (Int64.of_int global_ptr))
  end

let alloc_major_locked (major : major_heap) ~size ~tag : word =
  let rec try_chunks = function
    | [] ->
        let chunk =
          create_chunk ~base_address:major.next_base
            ~chunk_size:major.chunk_size ~card_size:major.card_size
        in
        major.next_base <- major.next_base + major.chunk_size;
        major.chunks <- chunk :: major.chunks;
        Option.get (alloc_chunk chunk ~size ~tag)
    | chunk :: rest -> (
        match alloc_chunk chunk ~size ~tag with
        | Some w -> w
        | None -> try_chunks rest)
  in
  try_chunks major.chunks

let find_chunk (major : major_heap) ptr : chunk =
  List.find
    (fun c -> ptr >= c.base_address && ptr < c.base_address + c.free_ptr)
    major.chunks

let read_field (major : major_heap) ptr i : word =
  let chunk = find_chunk major ptr in
  chunk.data.{ptr - chunk.base_address + i}

let write_field (major : major_heap) ptr i (w : word) =
  let chunk = find_chunk major ptr in
  chunk.data.{ptr - chunk.base_address + i} <- w

let write_barrier (d : minor_heap) (obj_ptr : int) (i : int) (new_val : word) =
  if is_ptr new_val then begin
    let chunk = find_chunk d.major obj_ptr in
    let hdr = chunk.data.{obj_ptr - chunk.base_address - 1} in
    if color hdr = color_black then begin
      let val_ptr = Int64.to_int (ptr_of_word new_val) in
      let val_chunk = find_chunk d.major val_ptr in
      let val_hdr = val_chunk.data.{val_ptr - val_chunk.base_address - 1} in
      if color val_hdr = color_white then begin
        val_chunk.data.{val_ptr - val_chunk.base_address - 1} <-
          set_color val_hdr color_gray;
        Queue.push val_ptr d.major.mark_queue
      end
    end;
    let field_addr = obj_ptr + i in
    if not (List.mem field_addr d.rem_set) then
      d.rem_set <- field_addr :: d.rem_set;
    let card_idx = (obj_ptr - chunk.base_address) / d.major.card_size in
    chunk.cards.{card_idx} <- 1
  end

let forward (d : minor_heap) (scan_queue : int Queue.t) ptr : word =
  let hdr = d.minor.{ptr - 1} in
  if is_forward hdr then d.minor.{ptr}
  else begin
    let sz = size hdr in
    let tg = tag hdr in
    let new_ptr_word = alloc_major_locked d.major ~size:sz ~tag:tg in
    let dst = Int64.to_int (ptr_of_word new_ptr_word) in
    let chunk = find_chunk d.major dst in
    for i = 0 to sz - 1 do
      chunk.data.{dst - chunk.base_address + i} <- d.minor.{ptr + i}
    done;
    d.minor.{ptr - 1} <- set_tag d.minor.{ptr - 1} tag_forward;
    d.minor.{ptr} <- new_ptr_word;
    d.promoted_words <- d.promoted_words + sz + 1;
    Queue.push dst scan_queue;
    new_ptr_word
  end

let scan_block (d : minor_heap) (scan_queue : int Queue.t) major_ptr =
  let chunk = find_chunk d.major major_ptr in
  let hdr = chunk.data.{major_ptr - chunk.base_address - 1} in
  let sz = size hdr in
  for i = 0 to sz - 1 do
    let w = chunk.data.{major_ptr - chunk.base_address + i} in
    if is_ptr w then begin
      let p = Int64.to_int (ptr_of_word w) in
      if p >= 0 && p < d.minor_size then
        write_field d.major major_ptr i (forward d scan_queue p)
    end
  done

let minor_gc (d : minor_heap) =
  Mutex.lock d.major.mutex;
  let scan_queue = Queue.create () in
  let rec scan_roots = function
    | None -> ()
    | Some r ->
        Array.iteri
          (fun i w ->
            if is_ptr w then begin
              let ptr = Int64.to_int (ptr_of_word w) in
              if ptr >= 0 && ptr < d.minor_size then
                r.values.(i) <- forward d scan_queue ptr
            end)
          r.values;
        scan_roots r.next
  in
  scan_roots d.roots;
  List.iter
    (fun field_addr ->
      let chunk = find_chunk d.major field_addr in
      let w = chunk.data.{field_addr - chunk.base_address} in
      if is_ptr w then begin
        let p = Int64.to_int (ptr_of_word w) in
        if p >= 0 && p < d.minor_size then
          chunk.data.{field_addr - chunk.base_address} <- forward d scan_queue p
      end)
    d.rem_set;
  while not (Queue.is_empty scan_queue) do
    let ptr = Queue.pop scan_queue in
    scan_block d scan_queue ptr
  done;
  d.rem_set <- [];
  Mutex.unlock d.major.mutex;
  d.young_ptr <- d.minor_size;
  d.minor_collections <- d.minor_collections + 1

let mark_gray (major : major_heap) ptr =
  let chunk = find_chunk major ptr in
  let hdr = chunk.data.{ptr - chunk.base_address - 1} in
  if color hdr = color_white then begin
    chunk.data.{ptr - chunk.base_address - 1} <- set_color hdr color_gray;
    Queue.push ptr major.mark_queue
  end

let mark_slice (major : major_heap) budget =
  let remaining = ref budget in
  while !remaining > 0 && not (Queue.is_empty major.mark_queue) do
    let ptr = Queue.pop major.mark_queue in
    let chunk = find_chunk major ptr in
    let hdr = chunk.data.{ptr - chunk.base_address - 1} in
    let sz = size hdr in
    chunk.data.{ptr - chunk.base_address - 1} <- set_color hdr color_black;
    for i = 0 to sz - 1 do
      let w = chunk.data.{ptr - chunk.base_address + i} in
      if is_ptr w then mark_gray major (Int64.to_int (ptr_of_word w))
    done;
    remaining := !remaining - sz - 1
  done

let sweep_chunk (chunk : chunk) =
  let i = ref 0 in
  while !i < chunk.free_ptr do
    let hdr = chunk.data.{!i} in
    let sz = size hdr in
    let total = sz + 1 in
    if color hdr = color_white then begin
      chunk.data.{!i} <- make ~size:sz ~color:color_white ~tag:0;
      (* FIX: THIS NEEDS TO BE FIXED! *)
      for j = 1 to sz do
        chunk.data.{!i + j} <- 0L
      done;
      chunk.free_words <- chunk.free_words + total
    end
    else chunk.data.{!i} <- set_color hdr color_white;
    i := !i + total
  done

let major_gc (major : major_heap) (roots : root option list) =
  Mutex.lock major.mutex;
  let rec mark_roots = function
    | None -> ()
    | Some r ->
        Array.iter
          (fun w ->
            if is_ptr w then mark_gray major (Int64.to_int (ptr_of_word w)))
          r.values;
        mark_roots r.next
  in
  List.iter mark_roots roots;
  mark_slice major max_int;
  List.iter sweep_chunk major.chunks;
  major.major_collections <- major.major_collections + 1;
  Mutex.unlock major.mutex

let alloc (d : minor_heap) ~size ~tag : word =
  if size > d.minor_size then begin
    Mutex.lock d.major.mutex;
    let w = alloc_major_locked d.major ~size ~tag in
    Mutex.unlock d.major.mutex;
    w
  end
  else begin
    let total = size + 1 in
    let new_ptr = d.young_ptr - total in
    if new_ptr < 0 then begin
      minor_gc d;
      let new_ptr2 = d.young_ptr - total in
      if new_ptr2 < 0 then begin
        Mutex.lock d.major.mutex;
        let w = alloc_major_locked d.major ~size ~tag in
        Mutex.unlock d.major.mutex;
        w
      end
      else begin
        d.minor.{new_ptr2} <- make ~size ~color:color_white ~tag;
        d.young_ptr <- new_ptr2;
        word_of_ptr (Int64.of_int (new_ptr2 + 1))
      end
    end
    else begin
      d.minor.{new_ptr} <- make ~size ~color:color_white ~tag;
      d.young_ptr <- new_ptr;
      word_of_ptr (Int64.of_int (new_ptr + 1))
    end
  end
