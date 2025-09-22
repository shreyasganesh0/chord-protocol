# Chord: A Scalable Peer-to-peer Lookup Protocol for Internet Applications

## Introduction
- peer to peer systems are systems where all nodes run equivalent level of appplication code, 
there is nohierarchial originization of nodes present.
- the core feature of p2p systems is efficient lookup of data locations
- chord, given a key, maps a key onto a node
    - depending on the applicaiton the node maybe responsible for the value associted with the key
- chord uses consistent hashing to assign keys to nodes
    - consistant hashing balances key-node distribution
    - allows for dynamic addition and removal of nodes without having to move keys around too much
- chord nodes only need routing information of O(logN) nodes of an N node system
- resolves lookups using O(logN) messages to all nodes
- performance degrades gracefully when routing information less than O(logN) nodes
    - useful for practical systems where nodes may leave and join and maintaining O(logN) 
    nodes information maybe hard
    - only 1 peice of informaiton is needed to be correct to garuntee correctness of 
    queries (thought it may be much slower)

## Related Work
- similar key-node mapping algorithms that emulate consistent hashing like algorithms
- the values associated with keys can be documents, address or arbitrary data item

### DNS
- normal DNS relies on name servers that store the domainname-ip mappings
- a chord based DNS would not have to rely on a central server
- hash the hostname to a key
- DNS requires a updated routing information NS records to allow clients to naviagate the hierarchy
- chord avoids naming hierarchy and can maintian ananlogous routing information

### Freenet
- a p2p storage system
- doesnt assign document responsiblilty to certain nodes
- uses lookups to search for cached copies of the document in peers
- tradeoff retrieval garuntee for anonymity
- chord can do the opposite where it doesnt provide anonymity but garuntees bounds on results

### Ohaha
- similar to freenet in terms of the querying system
- uses an offline computed tree to map logical addresses to the machines that store the documents

### Globe
- map object identifiers to locations of the objects
- creates a DNS like hierarchial mappings of the internet, geographically, 
topographically or admin based
- information about an object is stored in a leaf node
- it stores pointer caches to have shortcuts to answers
- globe partitions objects using hash like techniques
- chord can do the same hashing without having a hierarchy
- globe is better at exploiting node locality due to the hierarchy

### Tapestry
- closest to chord
- garuntees no more than logarithmic number of hops for queries like chord
- unlike chord it can garuntee that the max hop distance is not more than the node distance of 
the node that has the key
    - does this by taking network topology into account
    - makes it slightly more complex for nodes to join

### CAN
- d dimensional cartesian space that is used to create a distributed hash table
- state maintianed by CAN not dependant on the size of the network
- lookup cost increases faster than logN
- d is not created to vary with N so the lookup time can only match chords at the right N 
- also requires an additional protocol to remap the ids in the table with changes in the nodes

### GLS
- gls depens on geographical locations
- chord does a similar thing but with virutal network nodes

### Napster
- does search based on user inputted keywords
- chord uses unique ids instead
- napster uses a single point of reference for data location storage


## System Model
- Addresses problems like
    - Load balancing
        - distributed hash function to spread out keys
    - Decentralization
        - no central node which creates a more robust network of loads
    - Scalability
        - chord lookups grow with logN good for scalability
    - Availability
        - chord automatically updates internal tables when nodes join and leave
        - this allows nodes to almost always be found
    - Flexible naming
        - keys are in a flat namespace
        - gives flexibility on how the app wants to map names to keys

### Applications of chord
- Cooperative mirroring
    - multiple providers of content share, store and serve data
    - load balancing use case
- Time shared storage
    - for networks with intermittently connected nodes, users can store and display other users 
    data in exchange for having their data be available in other users systems
    - this is useful in systems where nodes arent always availble to have content 
    accessible from users eslsewhere
    - availabilitiy use
- Distributed indexes
    - key could be derived from searched terms
    - values could be list of machines that contain documents serving these words
- Large scale combinitorial search
    - like code breaking
    - where keys could be are candidate solutions (like crypto keys)
    - chord maps these keys to the machines that are responsible for solving them

## Chord Protocol

### Overview
- distributed computation of a hash function mapping keys to nodes responsible for them
- assigns nodes with consistent hashing
- high probability that nodes get an even number of keys and 
that redistribution of keys on node failure is 1/N keys
- imporves consistent hashing by removing the requirement that all nodes must know of each other
- chord only needs to know small amount of "routing information" of other nodes
- only needs to maintain knowledge for O(logN) nodes

### Consistent Hashing
- details
    - m bit identifier assigned to nodes using SHA-1 (can be something else)
    - chosen by hashing nodes IP
    - key identifier by hasing key
    - key -> original key and the image provided by the hash funciton
    - node -> node and image provided by the hash function
    - m must be large enough to avoid hash collisions
- steps
    - 2^m identifier circle created and keys are mapped to nodes % 2^m
    - key K is assigned to the node whose id is k or follows k in the id circle
        - called the sucessor of key k successor(k)
    - id circle (chord ring)
        - 0 to 2^m - 1 numbers
        - sucessor(k) is the first node clockwise from k 
        - imagine a circle with N2, N8, N16, N21, N32, N48, N56 for m=6
        - K10 would be mapped to N16, K23 and K27 would both be mapped to N32
    - when a node n enters some keys from n's successor will be reassigned to the node
    - when node n leaves keys from n will be mapped to n's successor
- each node is assigned at most (1+⋲ )K/N keys
- when there are N+1 nodes and the last node leaves, only O(K/N) keys responsibilty is changed
- "high probability"
    - nodes and keys are nodes are randomly chosen
    - in a non-adverserial network
    - thus the distribution of keys and nodes should be even based on the random nature
    - these garuntees are similar to the distribution of hashes based on random keys
    - the set of keys that produce a bad distribution of hashes for a given set of keys
        - this set is considered to be unlikely to occur for a good hash function
    - we can also choose a hash function based on the keys to get a good distribution
        - SHA-1 has a good distribution in general so that is used

### Simple Key Location
- basic key algorithm
- each node only needs to know how to contact its successor
- id queries can be passed around the circle until it straddles between the last two
- once it finds this the second node is the one that the id matches to
```
n.find_successor(id)
    if (id ∈ (n, successor)
        return successor
    else
        return succesor.find_successor(id)
```

### Scalable Key Location
- the simple algorithm is linear O(N)
    - since it goes from node to node until it reaches the node
- make it logN by storing additional routing information in a finger table
- for m bit id
    - each node maintains m entry routing table
    - O(logN) entries are distinct
- ith entry in the table at node n contains id of s that succeeds n by atleast 2^(i-1) on the circle
    - s is the ith finger of n
- a finget table entry contains chord id and IP address
- the first finger of n is the immediate succesor of n

- finget[k] = first node that succeeds (n + 2^(k - 1)) mod 2^m
- succesor = next node on the circle finger[1]
- predcessor = previous node on the id circle

- eg:
- imagine a system with node N1, N8, N14, N21, N32, N38, N42, N48, N51, N56
    let finger table of node 8 = 
    N8 + 1   | N14
    N8 + 2   | N14
    N8 + 4   | N14
    N8 + 8   | N21
    N8 + 16  | N32
    N8 + 32  | N42
    - these values (aka which node gets what) is determined by adding powers of 2 to the value 
    and rounding up to the nearest node as shown above
    - it only goes upto 32 since we assume m to be 6 aka 6 bit id so we can only store upto 64 N
    and values are upto + 2^5 i.e. 32 as seen
    - in this example as seen nodes only need to contain routing information to some subset of nodes
    - the ids are in increments of 2^i
    - this makes it easy to find the ith successor of a node here the 3rd successor for N8 would be N14
        - calculated as 8 + 2^(i-1) % 2^6 = 9 and the closest one to 9 is 14
    - if the key present in this is greater than the last node present we go to the last node 
    (in this case N42) and lookup what node corresponds to key k in that nodes finger table
- so given key k we do a lookup on the node table
    - lets k = 54 no node exists in 8s finger table
    - so it finds the closest one to it which is N42
    - N42 then check the closest one which would be N42 -> N51
    - now N51 has a neighbor N56 which satifies this key

### Node Joins and Stabilization
- when a node joins finger table and successor pointers must be updated
- this is done by a periodically running background job
- steps
    1. when n joins calls n.join
    ```
    n.join(n')
        predecessor = nil
        successor = n'.find_successor(n)
    ```
        - n' is an already existing node
        - it can also run n.create for new systems
    ```
    n.create()
        predecessor = nil
        successor = n;
    ```

    2. All nodes periodically run stabilize
    ```
    n.stabilize()
        x = successor.predecessor;
        if (x ∈ (n, successor))
            successor = x
        succesor.notify(n);
    ```
    ```
    n.notify(n')
        if (predecessor is nil or n' ∈ (predecessor, n))
            predecessor = n'
    ```
    - here stabilize is run to check if the current predecssor is still the node itself of 
    any other nodepoints to it now (as would occur if a node joins 
    the network between the current node and its successor)
    - makes the predecessor the new successor of n if that is the case
    - the notify is run on n so that the new node can also change its predecessor to n

    3. node periodically calls fix_fingers
    ```
    n.fix_fingers()
        next = next + 1
        if (next > m)
            next = 1 // bounds check on circular buffer
        finger[next] = find_succesor(n + 2^(next - 1))
    ```
    - new nodes init table using this
    - existing nodes update tables
    
    4. run check_predecessor periodically to update predecessor if the predecessor fails
    ```
    n.check_predecessor()
        if (predecessor has failed)
            predecessor = nil
    ```
- inconsistent state due to concurrent stabilizations will always be corrected
- if disjoint sets are produced may need to keep track of topology and fix them

### Impact of node joins on lookups
- one of 3 affects of a lookup for a node joining before stabilizaiton has finished
    1. good case: all lookup tables are reasonably current and it finds it in O(logN)
    2. successor pointers are correct but finger tables are not updated 
        - slower, but correct, lookups
    3. final case incorrect successor pointers in the joined regions
        - or keys may not have migrated to the node
        - lookup will fail
        - will have to manually retry
- unless a large number of nodes join the number of nodes that need to be hopped inbetween before finding the new node with the keys
    - in the case of not updated pointers and finger table
    - will still with high probability have lookups of logN
    - since not too many nodes will be inbetween the 2 node on either side of the key location
    - once its updated it will stabilize from one of those nodes

### Failure and Replication
- node relies on the invariant that all nodes know their succsessors
- if multiple nodes fail (example all nodes in the finger table of a node fail)
    - it wont be able to tell what node is its successor
    - this can lead to incorrect lookups/ overshooting and skipping nodes
        - a case where a node chooses a node from its finger table higher than the actual node
        - like key 39 from node 8 could be put on node 43 even though node 40 exists 
        because it thinks that this is the lowest if other nodes fail
- to mitigate this
    - each node has a successor list of r nodes
    - if a node doesnt respond it can use the next successor from its list
    - all r successors would have to fail simultaneously fail for incorrect ring state to occur

### Voluntary node departures
- could treat voluntary as failures
- but we can improve the performance using
    - could transfer all keys before leaving
    - could notify predecessor and successor of departure so they can update pointers and tables
        - also predecessor can update its successor list by removing n and addings 
        n's successor to its list
        - successor s will update its predecessor to n's predecessor

