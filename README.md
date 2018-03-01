# Distributed Processing in Haskell

In this project we have implemented the following distributed processing scenario, with the use of Control.Distributed.Process [Haskell library]:(https://hackage.haskell.org/package/distributed-process-0.7.3/docs/Control-Distributed-Process.html)

## Specification
Several nodes continuously send messages to other nodes in such way, that every message reaches every node.  Each message contains a deterministic random number n ∈ (0, 1]. That happens for some time, afterwards, during the grace period, each node prints out the following tuple: 
*<|m|, Σ(i * m~i~)> and i in [1, |m|]*
where m is the list of all messages sent by all nodes, ordered by sending time,
and m~i~ is the i-th message sent by some node. 
For the detailed specs of this program please refer to the spec.pdf document.

## How to run the program

## Communication Models and Ordering of Messages - Our implementation approach
In this section we describe our approach for solving the "ordering of messages" problem posed by the program specs.
### Problem Specification
We have N processes 
### Three different approaches  (Communication Models)
We have implemented the N nodes, as N processes spawned in the local Node (i.e., host), with the use of the `Control.Distributed.Process.spawnLocal`
function.
#### The Naive Approach
#### The Master Clock Approach
#### The Lamport Approach
----
In order to achieve a total ordering of the messages with respect to their "generation timestamp", I see 3 approaches: A) The "naive approach", where  our ordering is based on each node system clock (this is the approach I have implemented so far), B) the "master clock approach", where we have a specific process playing the role of the "master clock" and provides monotonically increased sequence numbers per request (the other processes before generating a new message, request for a sequence number from the master clock). Finally, I have found a 3rd solution to the problem based on the Leslie Lamport paper (https://lamport.azurewebsites.net/pubs/time-clocks.pdf), where every node maintains and uses as a sequence the maximum counter seen so far, when sends a message to another node. I will elaborate further on these 3 approaches, when I will submit my solution. Thank you for your help.

> Written with [StackEdit](https://stackedit.io/).
