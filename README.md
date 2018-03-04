# Distributed Processing in Haskell

In this project we have implemented the following distributed processing scenario, with the use of Control.Distributed.Process [Haskell library](https://hackage.haskell.org/package/distributed-process-0.7.3/docs/Control-Distributed-Process.html).

## Program Specification
Several nodes continuously send messages to other nodes in such way, that every message reaches every node.  Each message contains a deterministic random number n ∈ (0, 1]. That happens for some time, afterwards, during the grace period, each node prints out the following tuple: 
**<|m|, Σ(i * m~i~)> ,* 
where  i in [1, |m|]* and  m is the list of all messages sent by all nodes, ordered by sending time,
and m~i~ is the i-th message sent by some node. 
For the detailed specs of this program please refer to the [spec.pdf](https://github.com/nkarag/haskell-Distributed-Processing/blob/master/spec.pdf) document.
The important thing to notice is that the final result (sum), strongly depends on the ordering of the messages. In our case, according to the spec document  we want to order all the generated messages based on the timestamp of when they got sent.

## How to run the program
In order to run the program all you need to do is download the source code and then run:

    stack build
in order to compile the code (you need to have installed [stack](https://docs.haskellstack.org/en/stable/README/)). Then to invoke the program run:

    stack exec -- iohktest --send-for 2 --wait-for 4 --seed 7 --cmodel 3 --num-workers 10 2>&1 | tee output.txt
The program accepts 5 input parameters:
 `--send-for k`, which denotes how many seconds does the system send messages,
  `--wait-for l`,which denotes the length of the grace period in seconds (the grace period is the period where each worker node reads whatever unread messages it has left in his message queue and calculates and prints the final result),
  `--seed s`, which denotes the random generator seed
  `--cmodel m`, which denotes the communication model between the worker processes to be used. Currently, this parameter can accept only two values: 1 for the "Naive" communication model and 3 for the "Lamport" communication model. These models are explained in detail below.
  `--num-workers`, which denotes the number of worker processes to spawn.

The program sends output to both stdout and stderr (for debugging purposes). Since a lot of output is generated, it is a good idea to direct this output also to a file (output.txt) for  better inspection of the result. At the end, each worker process prints its final result, i.e., the above computation (Sum) based on the ordered list of messages that it has received. This appears at the end of the output.txt file, along with the setup that the program executed. For example:

    =====================================
      Program execution setup:
          sendTime = 2
          gracePeriod = 4
          seed = 7
          comm_model = Lamport
          numOfWorkers = 10
    =====================================
     --------- 
    Workers' acknowledgments follow:
    I am worker pid://127.0.0.1:10501:0:12 and my FINAL result is: (1497,633599.3864899322)
    I am worker pid://127.0.0.1:10501:0:11 and my FINAL result is: (1497,633599.3864899322)
    I am worker pid://127.0.0.1:10501:0:18 and my FINAL result is: (1497,633599.3864899322)
    I am worker pid://127.0.0.1:10501:0:15 and my FINAL result is: (1497,633599.3864899322)
    I am worker pid://127.0.0.1:10501:0:9 and my FINAL result is: (1497,633599.3864899322)
    From worker pid://127.0.0.1:10501:0:12 OK. Bye!
    From worker pid://127.0.0.1:10501:0:11 OK. Bye!
    From worker pid://127.0.0.1:10501:0:18 OK. Bye!
    From worker pid://127.0.0.1:10501:0:15 OK. Bye!
    From worker pid://127.0.0.1:10501:0:9 OK. Bye!
    I am worker pid://127.0.0.1:10501:0:17 and my FINAL result is: (1497,633599.3864899322)
    From worker pid://127.0.0.1:10501:0:17 OK. Bye!
    I am worker pid://127.0.0.1:10501:0:10 and my FINAL result is: (1497,633599.3864899322)
    From worker pid://127.0.0.1:10501:0:10 OK. Bye!
    I am worker pid://127.0.0.1:10501:0:14 and my FINAL result is: (1497,633599.3864899322)
    From worker pid://127.0.0.1:10501:0:14 OK. Bye!
    I am worker pid://127.0.0.1:10501:0:13 and my FINAL result is: (1497,633599.3864899322)
    From worker pid://127.0.0.1:10501:0:13 OK. Bye!
    I am worker pid://127.0.0.1:10501:0:16 and my FINAL result is: (1497,633599.3864899322)
    From worker pid://127.0.0.1:10501:0:16 OK. Bye!

Finally, in the [demo_runs](https://github.com/nkarag/haskell-Distributed-Processing/tree/master/demo_runs) folder, one can find several program outputs for various setups.
 In the next section, we expand on the communication models used for solving the message ordering problem.
## Communication Models and Ordering of Messages 
### Problem Specification
In this section we describe our approach for solving the "ordering of messages" problem posed by the program specs. As we have described we have N workers (processes), where each one for k seconds (sent-time) generates a random number and sends it to all other nodes (including itself). Each node reads all the messages that have been sent to him and computes the final result. However, in order for the final result (described above) to be correct, each worker node has to achieve a total ordering of the messages with respect to the time that the message was generated and sent.
In order to achieve this total ordering of the messages that each node stores in each local memory, we see three different approaches.
#### The Naive Approach
In this approach each process marks each message with a timestamp that is based on the host's system clock. More specifically, when each process enters the "send-time period", in each iteration it generates a new message, which includes a random number (the "data" part of the message) and a message generation timestamp, which is based on the current system time. Then it sends this message to all other processes including itself. During, the grace period, each process reads from its message queue, all received messages, and orders them in ascending order, based on this timestamp. Then it calculate the final result over this ordered list of messages.
The advantage of this approach is that it is fairly simple to implement. On the other hand, the assumption that all the system clocks of the hosts where each process is running will be synchronized so as to be able to produce a total ordering of the message is simply unrealistic.  In a true distributed setup this assumption does not hold and thus the total ordering will be wrong.
#### The Master Clock Approach
In this approach, we have a specific process playing the role of the "master clock" and provides monotonically increased sequence numbers per request, The other processes before generating a new message, request for a sequence number from the master clock and stamp each new message with this. 
The advantage of this method is obviously that by ordering the messages by this timestamp, all processes will produce a correct total order of the messages. However, the mere existence of a single process (the master clock), which is a shared resource, conflicts with notion of a "distributed system". This synchronized communication of all processes with the master clock, in order to get a "global timestamp", is a bottleneck for the system. Moreover, the master clock process becomes a single point of failure for the system. 
#### The Lamport Approach
The third approach is based on this [Leslie Lamport paper](https://lamport.azurewebsites.net/pubs/time-clocks.pdf), which describes a method for achieving a total ordering of asynchronous messages exchanged in a distributed system. The main idea here is that every process maintains and uses as a sequence (i.e., a timestamp) the maximum counter seen so far, when sends a message to another process. 
A Lamport timestamp bears no relationship to a physical time-of-day clock, but it
provides total ordering: if you have two timestamps, the one with a greater counter
value is the greater timestamp; if the counter values are the same, the one with the
greater process ID is the greater timestamp.
The key idea about Lamport timestamps, which makes them consistent with causality, is the following: every process keeps track of the maximum counter value it has seen so far, and includes that maximum on every message sent. When a process receives a message with a maximum counter value greater than its own counter value, it immediately increases its own counter to that maximum.
More specifically, during the send-time period, each process in each iteration, reads all messages available in its message queue, and computes the maximum counter of all these messages and its own counter. So the next message to be sent, gets as a timestamp the value: new_current_max_sequence + 1. As long as the maximum counter value is carried along with every message, this scheme ensures that the ordering from the Lamport timestamps is consistent with causality, because every causal dependency results in an increased timestamp.
Finally, during the grace period, no more sending of new messages takes place and each process reads any unreceived messages and appends them in its local list of all received messages. Then it sorts all the messages in ascending order by the Lamport timestamp and it computes the final result over this sorted list, which prints out on the screen.
#### Our Implementation 
In the current version of this program we have implemented two of the above communication models. Namely, the Naive approach and the Lamport approach. These can be specified when invoking the program with the input parameter `--cmodel m` which can take the values m = 1 and m = 3 respectively.

> Written with [StackEdit](https://stackedit.io/).

