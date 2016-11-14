open Lwt.Infix

let (/) = Filename.concat

let tmpdir = Filename.get_temp_dir_name () / "irmin-watcher"

let clean () =
  if Sys.file_exists tmpdir then (
    let _ = Sys.command (Printf.sprintf "rm -rf '%s'" tmpdir) in
    ()
  );
  Unix.mkdir tmpdir 0o755

let run f () =
  clean ();
  Lwt_main.run (f ())

let rec mkdir d =
  let perm = 0o0700 in
  try Unix.mkdir d perm
  with
  | Unix.Unix_error (Unix.EEXIST, "mkdir", _) -> ()
  | Unix.Unix_error (Unix.ENOENT, "mkdir", _) ->
    mkdir (Filename.dirname d);
    Unix.mkdir d perm

let write f d =
  let f = tmpdir / f in
  mkdir (Filename.dirname f);
  let oc = open_out f in
  output_string oc d;
  close_out oc

let remove f =
  try Unix.unlink (tmpdir / f)
  with e -> Alcotest.fail @@ Printexc.to_string e

let poll i () =
  let events = ref [] in
  let cond = Lwt_condition.create () in
  Irmin_watcher.hook >>= fun hook ->
  hook 0 tmpdir (fun e ->
      events := e :: !events;
      Lwt_condition.broadcast cond ();
      Lwt.return_unit
    ) >>= fun unwatch ->
  let reset () = events := [] in
  let rec wait () = match !events with
  | [] -> Lwt_condition.wait cond >>= wait
  | e  -> reset (); Lwt.return e
  in

  write "foo" ("foo" ^ string_of_int i);
  wait () >>= fun events ->
  Alcotest.(check (slist string String.compare)) "updte foo" ["foo"] events;

  remove "foo";
  wait () >>= fun events ->
  Alcotest.(check (slist string String.compare)) "remove foo" ["foo"] events;

  write "foo" ("foo" ^ string_of_int i);
  wait () >>= fun events ->
  Alcotest.(check (slist string String.compare)) "create foo" ["foo"] events;

  write "bar" ("bar" ^ string_of_int i);
  wait () >>= fun events ->
  Alcotest.(check (slist string String.compare)) "bar" ["bar"] events;
  unwatch ()

let random_letter () = Char.(chr @@ code 'a' + Random.int 26)

let rec random_filename () =
  Bytes.init (1 + Random.int 20) (fun _ -> random_letter ())
  |> Bytes.to_string
  |> fun x -> if x = "foo" || x = "bar" then random_filename () else x

let random_path n =
  let rec aux = function
  | 0 -> []
  | n -> random_filename () :: aux (n-1)
  in
  String.concat "/" (aux (n+1))

let prepare_fs n =
  let fs = Array.init n (fun i -> random_path 4, string_of_int i) in
  Array.iter (fun (k, v) -> write k v) fs

let random_polls n () =
  let rec aux = function
  | 0 -> Lwt.return_unit
  | i ->
      poll i () >>= fun () ->
      aux (i-1)
  in
  prepare_fs n;
  aux 100

let polling_tests = [
  "basic"  , `Quick, run (poll 0);
  "100s"   , `Quick, run (random_polls 100);
  "1000s"  , `Quick, run (random_polls 1000);
]

let mode = match Irmin_watcher.mode with
| `FSEvents -> "fsevents"
| `Inotify  -> "inotify"
| `Polling  -> "polling"

let tests = [
  mode, polling_tests;
]

let reporter () =
  let pad n x =
    if String.length x > n then x
    else x ^ Astring.String.v ~len:(n - String.length x) (fun _ -> ' ')
  in
  let report src level ~over k msgf =
    let k _ = over (); k () in
    let ppf = match level with Logs.App -> Fmt.stdout | _ -> Fmt.stderr in
    let with_stamp h _tags k fmt =
      let dt = Mtime.to_us (Mtime.elapsed ()) in
      Fmt.kpf k ppf ("%0+04.0fus %a %a @[" ^^ fmt ^^ "@]@.")
        dt
        Fmt.(styled `Magenta string) (pad 10 @@ Logs.Src.name src)
        Logs_fmt.pp_header (level, h)
    in
    msgf @@ fun ?header ?tags fmt ->
    with_stamp header tags k fmt
  in
  { Logs.report = report }

let () =
  Logs.set_level (Some Logs.Debug);
  Logs.set_reporter (reporter ());
  Alcotest.run "irmin-watch" tests
