import gleam/bit_array
import gleam/list

pub fn get_id_from_table_idx(t_idx: Int, b: BitArray) -> BitArray {

    let ret_bit_array = <<>> 
    let carry = 0
    let #(_, k_array) = list.range(0, 159)
    |> list.fold(#(carry, ret_bit_array), fn(acc, a) {
                               
                                   let assert Ok(curr_bit) = bit_array.slice(b, {159 - a}, 1)

                                   let #(carry, arr) = acc

                                   case a < {t_idx - 1} {

                                        True -> {
                                            
                                            #(0, <<curr_bit:bits, arr:bits>>)
                                        }

                                        False -> {

                                            case a == {t_idx - 1} {
                                                
                                                //0 + y + 1 cases

                                                True -> {

                                                    case curr_bit {

                                                        <<1:size(1)>> -> {                                  

                                                            #(1, <<<<0:size(1)>>:bits, arr:bits>>)
                                                        }

                                                        <<0:size(1)>> -> {

                                                            #(0, <<<<1:size(1)>>:bits, arr:bits>>)

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
                                                                    #(1, <<<<0:size(1)>>:bits, arr:bits>>)
                                                                }

                                                                <<0:size(1)>> -> {

                                                                    #(0, <<<<1:size(1)>>:bits, arr:bits>>)

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

                                                                    #(0, <<<<1:size(1)>>:bits, arr:bits>>)
                                                                }

                                                                <<0:size(1)>> -> {

                                                                    #(0, <<<<0:size(1)>>:bits, arr:bits>>)

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
                               }
       )

    echo k_array
    k_array

}
