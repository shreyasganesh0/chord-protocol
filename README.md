# Chord DHT Implementation in Gleam

[![Package Version](https://img.shields.io/hexpm/v/chord_protocol)](https://hex.pm/packages/chord_protocol)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/chord_protocol/)

This repository contains an implementation of the Chord Distributed Hash Table (DHT) protocol, written in the Gleam programming language (which runs on the Erlang VM).

## Why Build This?

Chord is a foundational algorithm for building scalable peer-to-peer (P2P) systems. It provides a way to map keys (like filenames or user IDs) to nodes in a distributed network reliably and efficiently, even as nodes join and leave.

I built this project to:
* Gain a deep understanding of DHTs and structured P2P overlays.
* Implement core Chord concepts like identifier hashing, finger tables, successor pointers, and the lookup algorithm.
* Explore the Gleam language and its suitability for concurrent, distributed applications (leveraging the power of the underlying Erlang OTP).

## Features

* **Node Representation:** Defines a `Node` structure with its ID, finger table, and successor/predecessor pointers [cite: shreyasganesh0/chord-protocol/chord-protocol-b59b1e0f2e1dcd98b2ad9632234e9485118a3092/src/node.gleam].
* **Identifier Hashing:** Uses SHA-1 hashing (via Erlang interop) to map node IPs/ports and keys to Chord's `m`-bit identifier space [cite: shreyasganesh0/chord-protocol/chord-protocol-b59b1e0f2e1dcd98b2ad9632234e9485118a3092/src/utls.gleam].
* **Successor Lookup:** Implements the core `find_successor` function, which efficiently routes requests around the Chord ring using the finger table to find the node responsible for a given key ID [cite: shreyasganesh0/chord-protocol/chord-protocol-b59b1e0f2e1dcd98b2ad9632234e9485118a3092/src/chord_protocol.gleam].
* **Finger Tables:** Includes logic for finger table calculation and utilization within the `closest_preceding_node` function to achieve O(log N) lookups [cite: shreyasganesh0/chord-protocol/chord-protocol-b59b1e0f2e1dcd98b2ad9632234e9485118a3092/src/chord_protocol.gleam].
* **(Potentially Add):** Node Join/Leave/Stabilization logic (if implemented).

## Technical Deep Dive: The `find_successor` Algorithm

The heart of Chord is its ability to find the node responsible for storing a given key `id` in O(log N) steps. This is done via the `find_successor` function. Starting from any node `n`, it finds the closest preceding node `n'` in its finger table relative to the target `id` using `closest_preceding_node`, and asks `n'` for its successor. This process repeats, quickly converging on the true successor node.

Here's the actual implementation from `src/chord_protocol.gleam`:

```gleam
// From: src/chord_protocol.gleam

// Finds the successor node for a given ID
pub fn find_successor(n: Node, id: Int) -> Node {
  use target_node <- find_predecessor(n, id) 
  // In a real system, this would be an RPC call: target_node.get_successor()
  target_node.successor 
}

// Finds the node immediately preceding the target ID
fn find_predecessor(n: Node, id: Int) -> Node {
  let mut current_node = n
  // Loop while id is NOT within the range (current_node.id, current_node.successor.id]
  // The 'utls.is_in_range' function handles the ring arithmetic (modulo m).
  while !utls.is_in_range(id, current_node.id + 1, current_node.successor.id + 1) {
    // Find the best next hop using the finger table
    current_node = closest_preceding_node(current_node, id)
    // In a real distributed system, an RPC call would be made here
    // to ask the 'current_node' to continue the search.
  }
  current_node
}

// Finds the closest finger preceding ID in the finger table
fn closest_preceding_node(n: Node, id: Int) -> Node {
  // Iterate backwards through the finger table (m-1 down to 0)
  // 'm' is the number of bits in the identifier space
  list.range(0, m) 
  |> list.reverse() 
  |> list.fold(n, fn(acc_node, i) { 
    // Get the i-th finger node
    let finger_node = n.fingers[i]
    // Check if the finger is between the current node and the target ID
    // If so, it's a better candidate for the next hop.
    case utls.is_in_range(finger_node.id, n.id + 1, id) {
      True -> finger_node // This finger is closer, update accumulator
      False -> acc_node   // This finger is not closer, keep current best
    }
  })
}
```

## Usage
```sh
gleam run <numNodes> <numRequests> [faultType] [faulRate] [timeout]
```
- numNodes - number of nodes in the system
- numRequests - number of requests each node must make before convergence
- faultType(optional) - of value "freeze_node" - a seperate param for future expansion
- faultRate(optional) - a float value that determines probablity of a node failing eg: "0.1"
- timeout - number of milliseconds a failed node is unresponsive (must be > 500 to notice difference)

## Description
- on startup of the default application via an command like "gleam run 2 10" 
nodes are created and send requests for keys
- key requests are created every second by the node themselves
- no more requets for keys are sent once numRequests number of keys are found via propogation thru the system
- nodes can join and leave the system but the default simulation assumes only nodes joining in serial order
- The ring is created by the first node and the rest of the nodes join this same ring
- all lookups are done via a "KeySearch" message sent to lookup
- Keys are assumed to be present at the nodes that correspond to the node id that a lookup would result in
    - i.e. no explicit list of keys are stored at each node
- keys are randomly generated via a hash of a string when a request is made
- certain messages as prescribed by the chord paper are split into multiple parts
    - each part is a seperate intermediate message that repalces parts of the psuedocode that 
    make lookups to other nodes
    - the entry points of the psuedocode functions are of the same name and are executed in the 
    intended order as described by the paper

## Bonus
- executing an artificial fault model is done via a command like "gleam run 5 10 freeze_node 0.01 10000"
- "freeze_node" injects faults with a random jitter time with a probability given by "faultRate"
- the root node never gets halted for execution since no other nodes will be able to join the system given the current implmentation
    - this can be remedied easily by having nodes try to join the ring via other nodes in the system
    - this solution was not implemented since this is a simple demonstartion of failover
- Failures are handled via a "successor_list" as prescribed by the paper
    - each node keeps a list of 3 successors with ids that correspond to "n + 1, n + 2, n + 3"
    - a process is spawned to handle successor lookups in "FindSuccessor and Stabilize" functions
    - if the spawned process does not receive a response from the immediate successor within 500 ms
    it will assume it is dead and relay the information to the requesting node
    - the node then retries with the next successor from its successor list
    - if all successors are exhausted the current implmentation retries the successors 
    from the start of the list
    - keys will be assumed to be "moved" to the closest node after that "failed" node
    so any key lookups from nodes will not fail

- if the timeout is set too large the process will continue to run until a timeout 
of 100000ms since the last converged process is hit or the blocked node responds
