# chord_protocol

[![Package Version](https://img.shields.io/hexpm/v/chord_protocol)](https://hex.pm/packages/chord_protocol)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/chord_protocol/)

## Team Members
- Shreyas Ganesh - UFID: 61738179
- S

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
