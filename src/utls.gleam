import gleam/bit_array
import gleam/list

pub fn get_id_from_table_idx(t_idx: Int, b: BitArray) -> BitArray {

    let left_shift_count = t_idx - 1
    let init_zeroes = <<0:size(1)>>

    let zeroes = case left_shift_count > 1 {

        True -> {

            list.range(2, left_shift_count)
            |> list.fold(init_zeroes, fn(acc, _) {
                                          <<acc:bits, <<0:size(1)>>:bits>>
                                      }
                )
        }

        False -> {

            init_zeroes
        }
    }
    let assert Ok(left_shifted_slice) = bit_array.slice(b, 0, left_shift_count)
    <<left_shifted_slice:bits, zeroes:bits>>
}
