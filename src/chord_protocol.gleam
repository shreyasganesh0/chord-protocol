import argv

import gleam/io
import gleam/int
import gleam/float
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
            Ok(#(num_nodes, num_reqs, "", 0.0, 1000))
        }

        [numnodes, numreqs, faultt, faultrate, tout] -> {

            use num_nodes <- result.try(result.map_error(int.parse(numnodes), fn(_) {InvalidArgs}))
            use num_reqs <- result.try(result.map_error(int.parse(numreqs), fn(_) {InvalidArgs}))
            use fault_t <- result.try(
                            fn() {

                                case faultt {

                                    "freeze_node" -> {

                                        Ok("freeze_node")
                                    }

                                    _ -> Error(InvalidArgs)
                                }
                            }()
                           )
            use fault_rate <- result.try(result.map_error(float.parse(faultrate), fn(_) {InvalidArgs}))
            use timeout <- result.try(result.map_error(int.parse(tout), fn(_) {InvalidArgs}))
            Ok(#(num_nodes, num_reqs, fault_t, fault_rate, timeout))
        }

        _ -> Error(WrongArgCount(5))
    }

    case ret {
        
        Ok(#(num_nodes, num_reqs, _fault_t, fault_rate, timeout)) -> {

            io.println("Got num nodes: " <> int.to_string(num_nodes) <> ", num_reqs: " <> int.to_string(num_reqs) <> "Got fault rate: " <> float.to_string(fault_rate) <> "Got timeout: " <> int.to_string(timeout))

            node.make_system(num_nodes, num_reqs, float.round(fault_rate *. 100.0), timeout)

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
