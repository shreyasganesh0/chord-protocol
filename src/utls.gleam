import gleam/bit_array
import gleam/order
//import gleam/io
//import gleam/int
//import gleam/float

import bigi

fn parse_bits(
    curr_idx: Int,
    t_idx: Int,
    carry: Int,
    ret_bits: BitArray,
    b: BitArray
    ) -> BitArray {


    case b {

        <<first_bit:size(1), rest:bits>> -> {

            let curr_bit = <<first_bit:size(1)>>

            let #(car, ret) = case curr_idx < {t_idx - 1} {

                True -> {
                    
                    #(0, <<curr_bit:bits, ret_bits:bits>>)
                }

                False -> {

                    case curr_idx == {t_idx - 1} {
                        
                        //0 + y + 1 cases

                        True -> {

                            case curr_bit {

                                <<1:size(1)>> -> {                                  

                                    #(1, <<<<0:size(1)>>:bits, ret_bits:bits>>)
                                }

                                <<0:size(1)>> -> {

                                    #(0, <<<<1:size(1)>>:bits, ret_bits:bits>>)

                                }
                                
                                _ -> {

                                    //invalid state
                                    panic as "bit wasnt 1 or 0"
                                }
                            }
                        }

                        False -> {

                            case carry {

                                //x + y + 0 cases
                                1 -> {

                                    case curr_bit {

                                        <<1:size(1)>> -> {                                  
                                            #(1, <<<<0:size(1)>>:bits, ret_bits:bits>>)
                                        }

                                        <<0:size(1)>> -> {

                                            #(0, <<<<1:size(1)>>:bits, ret_bits:bits>>)

                                        }
                                        
                                        _ -> {

                                            //invalid state
                                            panic as "bit wasnt 1 or 0"
                                        }
                                    }

                                }

                                0 -> {

                                    case curr_bit {

                                        <<1:size(1)>> -> {                                  

                                            #(0, <<<<1:size(1)>>:bits, ret_bits:bits>>)
                                        }

                                        <<0:size(1)>> -> {

                                            #(0, <<<<0:size(1)>>:bits, ret_bits:bits>>)

                                        }
                                        
                                        _ -> {

                                            //invalid state
                                            panic as "bit wasnt 1 or 0"
                                        }
                                    }

                                }
                                _ -> {

                                    //invalid state
                                    panic as "bit wasnt 1 or 0"
                                }
                            }
                        }
                    }
                }
            }
            
            parse_bits(curr_idx + 1, t_idx, car, ret, rest)

        }

        _ -> {

            ret_bits
        }
    }
}

fn big_int_calc(t_idx: Int, b: BitArray) -> BitArray {

    let assert Ok(bigi_id) = bigi.from_bytes(b, bigi.BigEndian, bigi.Unsigned)

    let bigi_two = bigi.from_int(2)
    
    let bigi_add_op = bigi.bitwise_shift_left(bigi_two, {t_idx - 1})
    let bigi_mod_op = bigi.bitwise_shift_left(bigi_two, {160})

    let assert Ok(ret) = bigi.add(bigi_id, bigi_add_op) 
    |> bigi.modulo(bigi_mod_op)
    |> bigi.to_bytes(bigi.BigEndian, bigi.Unsigned, {160 / 8})

    ret
}

pub fn get_id_from_table_idx(t_idx: Int, b: BitArray) -> BitArray {

    //let ret = parse_bits(0, t_idx, 0, <<>>, b)

    let ret = big_int_calc(t_idx, b)

    //echo ret

    //echo "above is ret"

    ret
}

pub fn check_bounds(
    search_id: BitArray,
    node_id: BitArray,
    successor_id: BitArray,
    li: Bool, 
    ri: Bool,
    ) -> Bool {

    let upper_bound = bit_array.compare(search_id, successor_id)|> order.to_int
    let lower_bound = bit_array.compare(search_id, node_id) |> order.to_int

    let right_check = case ri {

        False -> {

            upper_bound == -1
        }

        True -> {

            upper_bound <= 0
        }
    }

    let left_check = case li {

        False -> {

            lower_bound == 1
        }

        True -> {

            lower_bound >= 0
        }
    }

    case bit_array.compare(node_id, successor_id) {


        order.Gt -> {

            //io.println("hit wrap around case")
            {left_check} || { right_check}
        }

        order.Lt -> {

            //io.println("hit normal around case")
            {left_check} && {right_check}
        }

        order.Eq -> {True}
    }
}
