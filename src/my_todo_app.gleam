import gleam/dynamic/decode
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/result
import gleam/string

import argv
import simplifile

const filepath = "tasks.json"

const error_json = "Tasks file is not valid JSON or doesn't exist!"

const usage = "Usage:
todo ls - shows tasks
todo done - shows done tasks
todo add <task> - adds task
todo done <num> - completes the task
todo reset <done/cur/all> - resets tasks specified"

type Category {
  Tasks
  Done
}

fn get_by_pos(l: List(a), pos: Int) -> Result(a, Nil) {
  l
  |> list.split(pos - 1)
  |> fn(x) { x.1 |> list.first }
}

// designed to be used inside `use`
fn load_all(
  next: fn(#(List(String), List(String))) -> Result(a, Nil),
) -> Result(a, Nil) {
  case load(Tasks), load(Done) {
    Ok(tasks), Ok(done) -> next(#(tasks, done))
    _, _ -> Error(Nil)
  }
}

fn load(what: Category) -> Result(List(String), Nil) {
  let field = case what {
    Tasks -> "tasks"
    Done -> "done"
  }

  let parser = {
    use done <- decode.field(field, decode.list(decode.string))
    decode.success(done)
  }

  case simplifile.read(filepath) {
    Ok(data) ->
      json.parse(data, parser)
      |> result.replace_error(Nil)
    Error(_) -> Error(Nil)
  }
}

fn add_numeration(l: List(String), start_with: Int) -> List(String) {
  case l {
    [first, ..rest] ->
      list.append(
        [int.to_string(start_with) <> ". " <> first],
        add_numeration(rest, start_with + 1),
      )
    [] -> []
  }
}

fn add_task(task: String) -> Result(Nil, Nil) {
  use #(tasks, done) <- load_all()
  case overwrite(list.append(tasks, [task]), done) {
    Ok(_) -> Ok(Nil)
    Error(_) -> Error(Nil)
  }
}

fn done_task(num: Int) -> Result(String, Nil) {
  use #(tasks, done) <- load_all()
  use done_task <- result.try(get_by_pos(tasks, num))

  let res =
    overwrite(
      list.split(tasks, num - 1)
        // drops task by num
        |> fn(x) { #(x.0, list.drop(x.1, 1)) }
        |> fn(x) { list.append(x.0, x.1) },
      list.append(done, [done_task]),
    )

  case res {
    Ok(_) -> Ok(done_task)
    Error(_) -> Error(Nil)
  }
}

fn overwrite(
  tasks: List(String),
  done: List(String),
) -> Result(Nil, simplifile.FileError) {
  json.object([
    #("tasks", json.array(tasks, json.string)),
    #("done", json.array(done, json.string)),
  ])
  |> json.to_string
  |> simplifile.write(filepath, _)
}

fn reset(what: Category) -> Result(Nil, Nil) {
  use #(tasks, done) <- load_all()
  case what {
    Tasks -> overwrite([], done)
    Done -> overwrite(tasks, [])
  }
  |> result.replace_error(Nil)
}

pub fn main() -> Nil {
  case argv.load().arguments {
    ["ls"] ->
      case load(Tasks) {
        Ok(tasks) ->
          tasks
          |> add_numeration(1)
          |> list.append(["Your tasks are: "], _)
          |> string.join("\n")
          |> io.println
        Error(_) -> io.println_error(error_json)
      }
    ["done"] ->
      case load(Done) {
        Ok(tasks) ->
          tasks
          |> add_numeration(1)
          |> list.append(["Your completed tasks are:"], _)
          |> string.join("\n")
          |> io.println
        Error(_) -> io.println_error(error_json)
      }
    ["add", ..task] ->
      case add_task(string.join(task, " ")) {
        Ok(_) -> io.println("\"" <> string.join(task, " ") <> "\" was added!")
        Error(_) -> io.println_error(error_json)
      }
    ["done", str_num] ->
      case int.parse(str_num) {
        Ok(num) ->
          case done_task(num) {
            Ok(task) ->
              io.println("task \"" <> task <> "\" was completed! Congrats!")
            Error(_) -> io.println_error("Wrong pos!")
          }
        Error(_) -> io.println_error("dude, what did you type?")
      }
    ["reset", "cur"] ->
      case reset(Tasks) {
        Ok(_) -> io.println("Reset current tasks!")
        Error(_) -> io.println_error(error_json)
      }
    ["reset", "done"] ->
      case reset(Done) {
        Ok(_) -> io.println("Reset done tasks!")
        Error(_) -> io.println_error(error_json)
      }
    ["reset", "all"] ->
      case reset(Tasks), reset(Done) {
        Ok(_), Ok(_) -> io.println("Reset all!")
        _, _ -> io.println_error(error_json)
      }
    [_, ..] -> io.println(usage)
    [] -> io.println(usage)
  }
}
