import gleam/io
import gleam/int
import gleam/bit_array
import gleam/list
import gleam/order
import gleam/crypto
import gleam/option.{type Option, Some, None}
import gleam/dict.{type Dict}

import gleam/otp/actor
import gleam/otp/static_supervisor as supervisor
import gleam/otp/supervision

import gleam/erlang/process

import utls

type SuccessorUpdateType {

    KeySearch

    UpdatePos(t_idx: Int)

    UpdateSuccessor
}

type NodeMessage {

    DisplayTable

    RequestMessage

    StartBackgroundTasks

    FoundKey(
            key_id: BitArray,
            node_id: BitArray,
            hops: Int,
    )

    FindSuccessor(
                update_type: SuccessorUpdateType, 
                sender_sub: process.Subject(NodeMessage),
                search_id: BitArray,
                hops: Int,
    )

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
        node_id: BitArray,
    )
}

type NodeState {

    NodeState(
        seen_reqs: Int,
        num_reqs: Int,
        m: Int,
        next: Int,
        hops_sum: Int,
        waiting_for_join: Bool,
        node_id: BitArray,
        finger: Dict(Int, NodeIdentity),
        predecessor: Option(NodeIdentity),
        self_sub: process.Subject(NodeMessage),
        main_sub: process.Subject(Int),
        hasher: crypto.Hasher, 
    )
}

pub fn make_system(
    num_nodes: Int,
    num_reqs: Int,
    ) {

    let main_sub = process.new_subject()
    
    let m = 160

    let sup_build = supervisor.new(supervisor.OneForOne)

    let hasher = crypto.new_hasher(crypto.Sha1)

    let res = start(
                    hasher,
                    "0",
                    num_reqs,
                    main_sub,
                    m,
              )
    let assert Ok(first_sub) = res 
    let sup_build = supervisor.add(
                                sup_build,
                                supervision.worker(fn(){res}),
                      )

    let sub_list: List(process.Subject(NodeMessage)) = [first_sub.data]
    process.send(first_sub.data, Create)

    let #(sup_builder, _sub_list) = case num_nodes > 1 {

        True -> {

            list.range(1, num_nodes - 1)
            |> list.fold(#(sup_build, sub_list), fn(acc, node_id) {

                                                    let #(builder, sub_list) = acc
                                                    
                                                    let res = start(
                                                                    hasher,
                                                                    int.to_string(node_id),
                                                                    num_reqs,
                                                                    main_sub,
                                                                    m,
                                                              )
                                                    let assert Ok(sub) = res 

                                                    let sup_builder = supervisor.add(
                                                                                builder,
                                                                                supervision.worker(fn(){
                                                                                                    res
                                                                                                   }
                                                                                ),
                                                                      )

                                                    process.send(sub.data, Join(first_sub.data))

                                                    #(sup_builder, [sub.data, ..sub_list])
                                                }
                )
        } 

        False -> {

            #(sup_build, sub_list)

        }
    }
    let _ = supervisor.start(sup_builder)

    let nodes_hops = 0
    let sum = list.range(1, num_nodes)
    |> list.fold(nodes_hops, fn(acc, a) {

                            let assert Ok(hops) = process.receive(main_sub, 10000000)

                            acc + hops
                        }
    )

    io.println("Avg hops for all requests were: " <> int.to_string(sum / {num_reqs * num_nodes}))
    
}

fn start(
    hasher: crypto.Hasher,
    node_id: String,
    num_reqs: Int,
    main_sub: process.Subject(Int),
    m: Int,
    ) -> actor.StartResult(process.Subject(NodeMessage)) {

    actor.new_with_initialiser(1000, fn(sub) {init( 
                                                sub, hasher, node_id, num_reqs, main_sub, m
                                                )
                                     }
    )
    |> actor.on_message(handle_node)
    |> actor.start
}

fn init(
    sub: process.Subject(NodeMessage),
    hasher: crypto.Hasher,
    node_id: String,
    num_reqs: Int,
    main_sub: process.Subject(Int),
    m: Int,
    ) ->  Result(actor.Initialised(NodeState, NodeMessage, process.Subject(NodeMessage)), String) {

    let hash = crypto.hash_chunk(hasher, bit_array.from_string(node_id))
    |> crypto.digest

    //echo hash

    let init_state = NodeState(
                        seen_reqs: 0,
                        waiting_for_join: False,
                        num_reqs: num_reqs,
                        node_id: hash,
                        m: m,
                        next: 1,
                        hops_sum: 0,
                        hasher: hasher,
                        finger: dict.new(),
                        predecessor: None,
                        self_sub: sub,
                        main_sub: main_sub,
                     )
    Ok(actor.initialised(init_state)
    |> actor.returning(sub))

}

fn handle_node(
    state: NodeState,
    msg: NodeMessage,
    ) -> actor.Next(NodeState, NodeMessage) {

    case state.waiting_for_join {

        True -> {

            case msg {

                UpdateFinger(table_id, node_val) -> {

                    let s_nodeid = bit_array.inspect(state.node_id)
                    //io.println("[NODE]: " <> s_nodeid  <> " in update fingers")

                    let new_state = NodeState(
                                        ..state,
                                        waiting_for_join: False,
                                        finger: dict.insert(state.finger, table_id, node_val),
                                    )
                    process.send(node_val.node_sub, Notify(NodeIdentity(state.self_sub,state.node_id)))
                    process.send(state.self_sub, StartBackgroundTasks)

                    actor.continue(new_state)
                }

                FindSuccessor(update_t, og_sub, search_id, hops) -> {

                    let s_nodeid = bit_array.inspect(state.node_id)
                    let s_searchid = bit_array.inspect(search_id)
                    let assert Ok(NodeIdentity(successor_sub, successor_id)) = dict.get(state.finger, 1)
                    let s_successorid = bit_array.inspect(successor_id)

                    //io.println("[NODE]: " <> s_nodeid <> " in find_successor using successor id " <> s_successorid <> " and checking search id " <> s_searchid)
            

                    case utls.check_bounds(search_id, state.node_id, successor_id, False, True) {

                        True -> {

                            case update_t {

                                KeySearch -> {

                                    process.send(
                                        og_sub,
                                        FoundKey(search_id, successor_id, hops)
                                    )

                                }

                                UpdateSuccessor -> {

                    //io.println("[NODE]: " <> s_nodeid <> " in find_successor using successor id " <> s_successorid <> " and checking search id " <> s_searchid <> " sending update finger for t_idx 1")
                                    process.send(
                                        og_sub,
                                        UpdateFinger(1, NodeIdentity(successor_sub, successor_id))
                                    )
                                }

                                UpdatePos(next) -> {

                    //io.println("[NODE]: " <> s_nodeid <> " in find_successor using successor id " <> s_successorid <> " and checking search id " <> s_searchid <> " sending update finger for t_idx "<> int.to_string(next))
                                    process.send(
                                        og_sub,
                                        UpdateFinger(next, NodeIdentity(successor_sub, successor_id))
                                    )
                                }
                            }
                        }

                        False -> {

                    //io.println("[NODE]: " <> s_nodeid <> " in find_successor using successor id " <> s_successorid <> " and checking search id " <> s_searchid <> " sending to closest preceeding node")
                            let send_to_node = closest_preceding_node(
                                                    search_id, 
                                                    state.m,
                                                    NodeIdentity(state.self_sub, state.node_id),
                                                    state.finger,
                                                )
                            process.send(send_to_node, FindSuccessor(update_t, og_sub, search_id, hops + 1))
                            Nil
                        }
                    }
                    
                    actor.continue(state)
                }
                _ -> {

                    //requeue messages before node is ready
                    process.send(state.self_sub, msg)
                    actor.continue(state)
                }
            }
        }

        False -> {

            case msg {

                UpdateFinger(table_id, node_val) -> {

                    let s_nodeid = bit_array.inspect(state.node_id)
                    //io.println("[NODE]: " <> s_nodeid  <> " in update fingers")


                    let new_state = NodeState(
                            ..state,
                            finger: dict.insert(state.finger, table_id, node_val),
                    )

                    actor.continue(new_state)
                }

                DisplayTable -> {

                    let s_nodeid = bit_array.inspect(state.node_id)
                    //io.println("++++++++++++++++\n\n[NODE]: " <> s_nodeid <>" Printing table...\n")
                    //io.println("| Table Idx | Successor Node ")
                    dict.each(state.finger, fn(k, v) {
                                                let NodeIdentity(_node_sub, node_id) = v
                                                let s_nodeid = bit_array.inspect(node_id)
                                                //io.println("|         " <> int.to_string(k) <> " | " <> s_nodeid)
                                            }
                    )

                    //io.println("\n--------------\n")

                    actor.continue(state)
                }

                RequestMessage -> {

                    let s_nodeid = bit_array.inspect(state.node_id)
                    //io.println("[NODE]: " <> s_nodeid  <> " in req msg")

                    let rand_search_key = int.random(160) |> int.to_string

                    let hash = crypto.hash_chunk(state.hasher, bit_array.from_string(rand_search_key))
                    |> crypto.digest

                    process.send(state.self_sub, FindSuccessor(KeySearch, state.self_sub, hash, 1))
                    case state.num_reqs > state.seen_reqs {
                            True -> {
                                process.send_after(state.self_sub, 1000, RequestMessage)
                                Nil
                            }

                            False -> Nil
                    }

                    actor.continue(state)
                }


                StartBackgroundTasks -> {

                    let s_nodeid = bit_array.inspect(state.node_id)
                    //io.println("[NODE]: " <> s_nodeid  <> " in start background tasks")

                    process.send_after(state.self_sub, 1000, Stabilize) 
                    process.send_after(state.self_sub, 1000, FixFingers)
                    process.send_after(state.self_sub, 1000, CheckPredecessor)
                    case state.num_reqs > state.seen_reqs {
                            True -> {
                                process.send_after(state.self_sub, 1000, RequestMessage)
                                Nil
                            }

                            False -> Nil
                    }
                    //process.send_after(state.self_sub, 10000, DisplayTable)
                    actor.continue(state)
                }


                Stabilize -> {

                    let s_nodeid = bit_array.inspect(state.node_id)
                    //io.println("[NODE]: " <> s_nodeid  <> " in stabilize")

                    let assert Ok(NodeIdentity(successor_sub, _)) = dict.get(state.finger, 1)

                    process.send(successor_sub, QueryPredecessor(state.self_sub))

                    actor.continue(state)
                }


                QueryPredecessor(send_sub) -> {

                    let s_nodeid = bit_array.inspect(state.node_id)
                    //io.println("[NODE]: " <> s_nodeid  <> " in query pred")

                    process.send(send_sub, StabilizeContd(state.predecessor))

                    actor.continue(state)
                }


                StabilizeContd(maybe_pred_node) -> {

                    let s_nodeid = bit_array.inspect(state.node_id)
                    //io.println("[NODE]: " <> s_nodeid  <> " in stabilizeCnt")

                    let assert Ok(successor) = dict.get(state.finger, 1)
                    let NodeIdentity(successor_sub, successor_id) = successor

                    let new_state = case maybe_pred_node {

                        None -> {state}  

                        Some(pred_node) -> {

                            
                            case utls.check_bounds(pred_node.node_id, state.node_id,
                                successor_id, False, False) {

                                True -> {

                                    NodeState(
                                        ..state,
                                        finger: dict.insert(state.finger, 1, pred_node),
                                    )
                                }

                                False -> {

                                    state
                                }
                            }
                        }
                    }

                    process.send(successor_sub, Notify(NodeIdentity(state.self_sub, state.node_id)))

                    process.send_after(state.self_sub, 1000, Stabilize) 
                    actor.continue(new_state)
                }


                Notify(possible_pred_node) -> {

                    let s_nodeid = bit_array.inspect(state.node_id)
                    //io.println("[NODE]: " <> s_nodeid  <> " in notify")

                    let new_state = case state.predecessor {

                        None -> {

                                    NodeState(
                                        ..state,
                                        predecessor: Some(possible_pred_node),
                                    )
                        }

                        Some(node) -> {

                            let NodeIdentity(_pred_sub, pred_id) = node

                            case utls.check_bounds(possible_pred_node.node_id, pred_id, 
                                state.node_id, False, False)  {

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

                    let s_nodeid = bit_array.inspect(state.node_id)
                    //io.println("[NODE]: " <> s_nodeid  <> " in fix fingers")

                    let nxt = case state.next + 1 > state.m {

                        True -> {

                           1 
                        }

                        False -> {

                            state.next + 1
                        }
                    }

                    let check_id = utls.get_id_from_table_idx(nxt, state.node_id)
                    process.send(state.self_sub, FindSuccessor(
                                                    UpdatePos(nxt),
                                                    state.self_sub,
                                                    check_id, //have to add the next offset value to this
                                                    1,
                                                 )
                    )
                    let new_state = NodeState(
                                        ..state,
                                        next: nxt
                                    )


                    process.send_after(state.self_sub, 1000, FixFingers)
                    actor.continue(new_state)
                }




                CheckPredecessor -> {

                    let s_nodeid = bit_array.inspect(state.node_id)
                    //io.println("[NODE]: " <> s_nodeid  <> " in check pred")

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
                    process.send_after(state.self_sub, 1000, CheckPredecessor)
                    actor.continue(new_state)
                }

                FoundKey(key_id, at_node_id, hops) -> {

                    let s_keyid = bit_array.inspect(key_id)
                    let s_atnodeid = bit_array.inspect(at_node_id)
                    let s_nodeid = bit_array.inspect(state.node_id)

                    //io.println("Found key: " <> s_keyid <> " at node: " <> s_atnodeid)

                    let new_hops_sum = hops + state.hops_sum

                    //io.println("node: " <> s_nodeid <> " has seen " <> int.to_string(state.seen_reqs))

                    let new_state = case {state.seen_reqs + 1} == state.num_reqs {

                        True -> {

                            io.println("Found all " <> int.to_string(state.num_reqs) <> " keys...")
                            io.println("Average node hops for node: " <> s_nodeid <> " is " <> int.to_string(new_hops_sum / state.num_reqs))
                            process.send(state.main_sub, new_hops_sum)
                            NodeState(
                                ..state,
                                seen_reqs: state.seen_reqs + 1,
                                hops_sum: new_hops_sum,
                            )

                        }

                        False -> {

                            case {state.seen_reqs + 1} > state.num_reqs {

                                True -> {

                                    state
                                }

                                False -> {

                                    NodeState(
                                        ..state,
                                        seen_reqs: state.seen_reqs + 1,
                                        hops_sum: new_hops_sum,
                                    )

                                }
                            }

                        }
                    } 

                    actor.continue(new_state)
                }


                FindSuccessor(update_t, og_sub, search_id, hops) -> {

                    let s_nodeid = bit_array.inspect(state.node_id)
                    let s_searchid = bit_array.inspect(search_id)
                    let assert Ok(NodeIdentity(successor_sub, successor_id)) = dict.get(state.finger, 1)
                    let s_successorid = bit_array.inspect(successor_id)

                    //io.println("[NODE]: " <> s_nodeid <> " in find_successor using successor id " <> s_successorid <> " and checking search id " <> s_searchid)
            

                    case utls.check_bounds(search_id, state.node_id, successor_id, False, True) { 

                        True -> {

                            case update_t {

                                KeySearch -> {

                                    process.send(
                                        og_sub,
                                        FoundKey(search_id, successor_id, hops)
                                    )

                                }

                                UpdateSuccessor -> {

                    //io.println("[NODE]: " <> s_nodeid <> " in find_successor using successor id " <> s_successorid <> " and checking search id " <> s_searchid <> " sending update finger for t_idx 1")
                                    process.send(
                                        og_sub,
                                        UpdateFinger(1, NodeIdentity(successor_sub, successor_id))
                                    )
                                }

                                UpdatePos(next) -> {

                    //io.println("[NODE]: " <> s_nodeid <> " in find_successor using successor id " <> s_successorid <> " and checking search id " <> s_searchid <> " sending update finger for t_idx "<> int.to_string(next))
                                    process.send(
                                        og_sub,
                                        UpdateFinger(next, NodeIdentity(successor_sub, successor_id))
                                    )
                                }
                            }
                        }

                        False -> {

                    //io.println("[NODE]: " <> s_nodeid <> " in find_successor using successor id " <> s_successorid <> " and checking search id " <> s_searchid <> " sending to closest preceeding node")
                            let send_to_node = closest_preceding_node(
                                                    search_id, 
                                                    state.m,
                                                    NodeIdentity(state.self_sub, state.node_id),
                                                    state.finger,
                                                )
                            process.send(send_to_node, FindSuccessor(update_t, og_sub, search_id, hops + 1))
                            Nil
                        }
                    }
                    
                    actor.continue(state)
                }


                Create -> {

                    let s_nodeid = bit_array.inspect(state.node_id)
                    //io.println("[NODE]: " <> s_nodeid <> " in create")

                    let new_state = NodeState(
                                        ..state,
                                        predecessor: None,
                                        finger: dict.insert(
                                                    state.finger,
                                                    1,
                                                    NodeIdentity(state.self_sub, state.node_id),
                                                 ),
                                    )
                    process.send(state.self_sub, StartBackgroundTasks)
                    actor.continue(new_state)
                }


                Join(chord_sub) -> {
                    
                    let s_nodeid = bit_array.inspect(state.node_id)
                    //io.println("[NODE]: " <> s_nodeid <> " in join")

                    process.send(chord_sub, FindSuccessor(UpdateSuccessor, state.self_sub, state.node_id, 1))

                    let new_state = NodeState(
                                        ..state,
                                        waiting_for_join: True,
                                        predecessor: None, 
                                    )

                    actor.continue(new_state)
                }

                _ -> actor.continue(state)
            }
        }
    }
}


fn closest_preceding_node(
    search_id: BitArray,
    m: Int,
    sender_node: NodeIdentity,
    finger: Dict(Int, NodeIdentity)
    ) -> process.Subject(NodeMessage) {

    let NodeIdentity(sender_sub, sender_id) = sender_node

    let NodeIdentity(ret_sub, _) = list.range(m, 1)
    |> list.fold_until(sender_node, fn(sender_node, a) {
                                        
                                      // let assert Ok(curr_power) = {int.power(2, int.to_float(a - 1)) 
                                      //                             +. int.to_float(curr_id)}
                                      //                             |> int.power(2, int.to_float(m))

                                      // let t_idx = float.round(curr_power)
                                      case dict.get(finger, a) { 

                                          Ok(NodeIdentity(curr_sub, curr_val)) -> {

                                              case utls.check_bounds(curr_val, sender_id,
                                                search_id, False, False) {

                                                  True -> {

                                                      //io.println("[NODE]: " <> bit_array.inspect(sender_node.node_id) <> " hit stop")
                                                      list.Stop(NodeIdentity(curr_sub, curr_val))
                                                  }

                                                  False -> list.Continue(sender_node)
                                               }
                                           }

                                          Error(_) -> {

                                              //have to check edge case to see if it continued till the end or stopped at the end
                                              list.Continue(sender_node)
                                          }
                                      }
                                  }
        )

    ret_sub
}
