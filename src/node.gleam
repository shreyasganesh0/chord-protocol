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

    UpdateSuccessor(node: NodeIdentity)

    FindSuccessor(node: NodeIdentity)

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

    let sub_list: List(process.Subject(NodeMessage)) = []

    let #(sup_builder, _sub_list) = list.range(1, num_nodes)
    |> list.fold(#(sup_build, sub_list), fn(acc, _) {

                                        let #(builder, sub_list) = acc
                                        
                                        let res = start(
                                                        num_reqs,
                                                        m,
                                                  )
                                        let assert Ok(sub) = res 

                                        let sup_builder = supervisor.add(
                                                                    builder,
                                                                    supervision.worker(fn(){res}),
                                                          )

                                        #(sup_builder, [sub.data, ..sub_list])
                                    }
        )
    let _ = supervisor.start(sup_builder)

    list.each(sub_list, fn(node) {

                        }
    )
    
    process.receive_forever(main_sub)
}

fn start(
    num_reqs: Int,
    m: Int,
    ) -> actor.StartResult(process.Subject(NodeMessage)) {

    actor.new_with_initialiser(1000, fn(sub) {init(sub, num_reqs, m)})
    |> actor.on_message(handle_node)
    |> actor.start
}

fn init(
    sub: process.Subject(NodeMessage),
    num_reqs: Int,
    m: Int,
    ) ->  Result(actor.Initialised(NodeState, NodeMessage, process.Subject(NodeMessage)), String) {


    let init_state = NodeState(
                        seen_reqs: 0,
                        num_reqs: num_reqs,
                        node_id: 0,
                        m: m,
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

            actor.continue(state)
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

        FindSuccessor(NodeIdentity(node_sub, node_id)) -> {

            let assert Ok(NodeIdentity(successor_sub, successor_id)) = list.first(state.successor_list)
            case node_id > state.node_id && node_id <= successor_id {

                True -> {

                    process.send(node_sub, UpdateSuccessor(NodeIdentity(successor_sub, successor_id)))
                }

                False -> {

                    let send_to_node = closest_preceding_node(
                                            node_id, 
                                            state.m,
                                            NodeIdentity(state.self_sub, state.node_id),
                                            state.finger,
                                        )
                    process.send(send_to_node, FindSuccessor(NodeIdentity(node_sub, node_id)))
                }
            }

            actor.continue(state)
        }

        Join(chord_sub) -> {
            
            process.send(chord_sub, FindSuccessor(NodeIdentity(state.self_sub, state.node_id)))

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

                                      let assert Ok(NodeIdentity(curr_sub,curr_val)) = dict.get(finger, a) 

                                      case {curr_val > curr_id} && {curr_val < node_id}{

                                          True -> list.Stop(NodeIdentity(curr_sub, curr_val))

                                          False -> list.Continue(curr_node)
                                      }
                                  }
        )

    ret_sub
}
