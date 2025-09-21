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
