import argv

import gleam/io
import gleam/int
import gleam/result

import node

type ParseError {

    InvalidArgs
    WrongArgCount(required: Int)
}

pub fn main() -> Nil {

    let ret = case argv.load().arguments {

        [numnodes, numreqs] -> {

            use num_nodes <- result.try(result.map_error(int.parse(numnodes), fn(_) {InvalidArgs}))
            use num_reqs <- result.try(result.map_error(int.parse(numreqs), fn(_) {InvalidArgs}))
            Ok(#(num_nodes, num_reqs))
        }

        _ -> Error(WrongArgCount(3))
    }

    case ret {
        
        Ok(#(num_nodes, num_reqs)) -> {

            io.println("Got num nodes: " <> int.to_string(num_nodes) <> ", num_reqs: " 
                <> int.to_string(num_reqs))

            node.make_system(num_nodes, num_reqs)

        }

        Error(err) -> {

            case err {

                InvalidArgs -> {

                    io.println("Invalid args passed")
                }

                WrongArgCount(c) -> {

                    io.println("Invalid number of args, require " <> int.to_string(c))
                    io.println("Usage: ./chord_protocol numNodes, numReqs")
                }

            }
        }
    }
}
