import gleam/io
import gleam/int
import gleam/float
import gleam/list
import gleam/option.{type Option, Some, None}
import gleam/dict.{type Dict}

import gleam/otp/actor
import gleam/otp/static_supervisor as supervisor
import gleam/otp/supervision

import gleam/erlang/process


type NodeMessage {

    RequestMessage

    StartBackgroundTasks

    UpdateSuccessor(node: NodeIdentity)

    FindSuccessor(table_id: Option(Int), sender_sub: process.Subject(NodeMessage), search_id: Int)

    Stabilize

    QueryPredecessor(send_sub: process.Subject(NodeMessage)) 

    StabilizeContd(pred_node: Option(NodeIdentity)) 

    Notify(possible_pred_node: NodeIdentity)

    FixFingers 

    UpdateFinger(table_id: Int, node: NodeIdentity) 

    CheckPredecessor 

    Create

    Join(sub: process.Subject(NodeMessage))
}

type NodeIdentity {

    NodeIdentity(
        node_sub: process.Subject(NodeMessage),
        node_id: Int,
    )
}

type NodeState {

    NodeState(
        seen_reqs: Int,
        num_reqs: Int,
        node_id: Int,
        m: Int,
        next: Int,
        successor_list: List(NodeIdentity),
        finger: Dict(Int, NodeIdentity),
        predecessor: Option(NodeIdentity),
        self_sub: process.Subject(NodeMessage),
    )
}

pub fn make_system(
    num_nodes: Int,
    num_reqs: Int,
    ) {

    let main_sub = process.new_subject()

    let assert Ok(tmp) = {int.to_float(num_nodes) |> float.logarithm}
    let assert Ok(log_two) = float.logarithm(2.0)
    let m = {{tmp /. log_two } |> float.round} + 1

    let sup_build = supervisor.new(supervisor.OneForOne)


    let res = start(
                    0,
                    num_reqs,
                    m,
              )
    let assert Ok(first_sub) = res 
    let sup_build = supervisor.add(
                                sup_build,
                                supervision.worker(fn(){res}),
                      )

    let sub_list: List(process.Subject(NodeMessage)) = [first_sub.data]
    process.send(first_sub.data, Create)

    let #(sup_builder, _sub_list) = list.range(1, num_nodes)
    |> list.fold(#(sup_build, sub_list), fn(acc, node_id) {

                                        let #(builder, sub_list) = acc
                                        
                                        let res = start(
                                                        node_id,
                                                        num_reqs,
                                                        m,
                                                  )
                                        let assert Ok(sub) = res 

                                        let sup_builder = supervisor.add(
                                                                    builder,
                                                                    supervision.worker(fn(){res}),
                                                          )

                                        process.send(sub.data, Join(first_sub.data))

                                        #(sup_builder, [sub.data, ..sub_list])
                                    }
        )
    let _ = supervisor.start(sup_builder)

    list.each(sub_list, fn(node) {

                            process.send(node, StartBackgroundTasks)
                        }
    )
    
    process.receive_forever(main_sub)
}

fn start(
    node_id: Int,
    num_reqs: Int,
    m: Int,
    ) -> actor.StartResult(process.Subject(NodeMessage)) {

    actor.new_with_initialiser(1000, fn(sub) {init( 
                                                sub, node_id, num_reqs, m
                                                )
                                     }
    )
    |> actor.on_message(handle_node)
    |> actor.start
}

fn init(
    sub: process.Subject(NodeMessage),
    node_id: Int,
    num_reqs: Int,
    m: Int,
    ) ->  Result(actor.Initialised(NodeState, NodeMessage, process.Subject(NodeMessage)), String) {


    let init_state = NodeState(
                        seen_reqs: 0,
                        num_reqs: num_reqs,
                        node_id: node_id,
                        m: m,
                        next: 0,
                        successor_list: [],
                        finger: dict.new(),
                        predecessor: None,
                        self_sub: sub,
                     )
    Ok(actor.initialised(init_state)
    |> actor.returning(sub))

}

fn handle_node(
    state: NodeState,
    msg: NodeMessage,
    ) -> actor.Next(NodeState, NodeMessage) {

    case msg {

        RequestMessage -> {

            io.println("[NODE]: " <> int.to_string(state.node_id) <> " saw req")

            let new_state = NodeState(
                                ..state,
                                seen_reqs: state.seen_reqs + 1,
                            )

            case new_state.seen_reqs < state.num_reqs {

                True -> actor.continue(new_state)

                False -> {

                    actor.continue(new_state)
                }
            }

            actor.continue(new_state)
        }

        StartBackgroundTasks -> {

            process.send(state.self_sub, Stabilize) 
            process.send(state.self_sub, FixFingers)
            process.send(state.self_sub, CheckPredecessor)
            process.send_after(state.self_sub, 1000, RequestMessage)
            process.send_after(state.self_sub, 500, StartBackgroundTasks)

            actor.continue(state)
        }

        Stabilize -> {

            let assert Ok(NodeIdentity(successor_sub, _)) = list.first(state.successor_list)

            process.send(successor_sub, QueryPredecessor(state.self_sub))

            actor.continue(state)
        }

        QueryPredecessor(send_sub) -> {

            process.send(send_sub, StabilizeContd(state.predecessor))

            actor.continue(state)
        }

        StabilizeContd(maybe_pred_node) -> {

            let assert Ok(successor) = list.first(state.successor_list)
            let NodeIdentity(successor_sub, successor_id) = successor

            let new_state = case maybe_pred_node {

                None -> {state}  

                Some(pred_node) -> {

                    
                    case pred_node.node_id > state.node_id && pred_node.node_id < successor_id {

                        True -> {

                            NodeState(
                                ..state,
                                successor_list: [pred_node],
                            )
                        }

                        False -> {

                            state
                        }
                    }
                }
            }

            process.send(successor_sub, Notify(NodeIdentity(state.self_sub, state.node_id)))

            actor.continue(new_state)
        }

        Notify(possible_pred_node) -> {

            let new_state = case state.predecessor {

                None -> {state}

                Some(node) -> {

                    let NodeIdentity(_pred_sub, pred_id) = node

                    case {possible_pred_node.node_id > pred_id} && 
                        {possible_pred_node.node_id < state.node_id} {


                       True -> {

                            NodeState(
                                ..state,
                                predecessor: Some(possible_pred_node),
                            )

                        } 

                        False -> {

                            state
                        }

                    }

                }
            }

            actor.continue(new_state)
        }

        FixFingers -> {
            let nxt = case state.next + 1 > state.m {

                True -> {

                    1
                }

                False -> {

                    state.next + 1
                }
            }

            let assert Ok(f_idx) = int.power(2, int.to_float(nxt - 1))
            process.send(state.self_sub, FindSuccessor(
                                            Some(nxt),
                                            state.self_sub,
                                            float.round(f_idx),
                                         )
            )
            let new_state = NodeState(..state, next: nxt)

            actor.continue(new_state)
        }

        UpdateFinger(table_id, node_val) -> {

            let new_state = NodeState(
                                ..state,
                                finger: dict.insert(state.finger, table_id, node_val),
                            )
            actor.continue(new_state)
        }

        CheckPredecessor -> {

            let new_state = case state.predecessor {

                None -> state

                Some(node) -> {

                    let NodeIdentity(node_sub, _) = node

                    case process.subject_owner(node_sub) {

                        Error(_) -> {

                            NodeState(
                                ..state,
                                predecessor: None,
                            )
                        }

                        Ok(pid) -> {

                            case process.is_alive(pid) {

                                True -> {state}

                                False -> {
                                    NodeState(
                                        ..state,
                                        predecessor: None,
                                    )
                                }
                            }
                        }

                    }
                }
            }
            actor.continue(new_state)
        }


        Create -> {

            let new_state = NodeState(
                                ..state,
                                predecessor:  None,
                                successor_list:  [NodeIdentity(state.self_sub, state.node_id),
                                                ..state.successor_list],
                            )

            actor.continue(new_state)
        }

        UpdateSuccessor(node) -> {

            let new_state = NodeState(
                                ..state,
                                successor_list: [node, ..state.successor_list],
                            )
            actor.continue(new_state)
        }

        FindSuccessor(nxt, og_sub, node_id) -> {

            let assert Ok(NodeIdentity(successor_sub, successor_id)) = list.first(state.successor_list)
            case node_id > state.node_id && node_id <= successor_id {

                True -> {

                    case nxt {

                        None -> {

                            process.send(og_sub,
                            UpdateSuccessor(NodeIdentity(successor_sub, successor_id)))
                        }

                        Some(next) -> {

                            process.send(og_sub,
                            UpdateFinger(next, NodeIdentity(successor_sub, successor_id)))
                        }
                    }
                }

                False -> {

                    let send_to_node = closest_preceding_node(
                                            node_id, 
                                            state.m,
                                            NodeIdentity(state.self_sub, state.node_id),
                                            state.finger,
                                        )
                    process.send(send_to_node, FindSuccessor(nxt, og_sub, node_id))
                }
            }

            actor.continue(state)
        }

        Join(chord_sub) -> {
            
            process.send(chord_sub, FindSuccessor(None, state.self_sub, state.node_id))

            let new_state = NodeState(
                                ..state,
                                predecessor: None, 
                            )

            actor.continue(new_state)
        }
    }
}


fn closest_preceding_node(
    node_id: Int,
    m: Int,
    curr_node: NodeIdentity,
    finger: Dict(Int, NodeIdentity)
    ) -> process.Subject(NodeMessage) {

    let NodeIdentity(curr_sub, curr_id) = curr_node

    let NodeIdentity(ret_sub, _) = list.range(m, 1)
    |> list.fold_until(curr_node, fn(curr_node, a) {

                                      let assert Ok(NodeIdentity(_curr_sub, curr_val)) = dict.get(finger, a) 

                                      case {curr_val > curr_id} && {curr_val < node_id}{

                                          True -> list.Stop(NodeIdentity(curr_sub, curr_val))

                                          False -> list.Continue(curr_node)
                                      }
                                  }
        )

    ret_sub
}
