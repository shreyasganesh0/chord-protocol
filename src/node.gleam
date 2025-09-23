import gleam/list

import gleam/otp/actor
import gleam/otp/static_supervisor as supervisor
import gleam/otp/supervision

import gleam/erlang/process


type NodeMessage {

    NodeMessage
}

type NodeState {

    NodeState(
        seen_reqs: Int,
        num_reqs: Int,
    )
}

pub fn make_system(
    num_nodes: Int,
    num_reqs: Int,
    ) {

    let main_sub = process.new_subject()

    let init_state = NodeState(
                        seen_reqs: 0,
                        num_reqs: num_reqs,
                     )
    let sup_build = supervisor.new(supervisor.OneForOne)

    let sub_list: List(process.Subject(NodeMessage)) = []

    let #(sup_builder, _sub_list) = list.range(1, num_nodes)
    |> list.fold(#(sup_build, sub_list), fn(acc, _) {

                                        let #(builder, sub_list) = acc
                                        
                                        let res = start(init_state)
                                        let assert Ok(sub) = res 

                                        let sup_builder = supervisor.add(
                                                                    builder,
                                                                    supervision.worker(fn(){res}),
                                                          )

                                        #(sup_builder, [sub.data, ..sub_list])
                                    }
        )
    let _ = supervisor.start(sup_builder)
    
    process.receive_forever(main_sub)
}

fn start(
    state: NodeState,
    ) -> actor.StartResult(process.Subject(NodeMessage)) {

    actor.new(state)
    |> actor.on_message(handle_node)
    |> actor.start
}

fn handle_node(
    state: NodeState,
    msg: NodeMessage,
    ) -> actor.Next(NodeState, NodeMessage) {

    case msg {

        NodeMessage -> {

            actor.continue(state)
        }
    }
}
