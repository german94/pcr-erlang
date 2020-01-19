# pcr-erlang
PCR pattern implementation in Erlang programming language

## How to run it
- Download Erlang from: https://www.erlang.org/
- Open a terminal in the project's root directory and run ```erl -make``` in order to compile the project
- ```mkdir ebin; cd ebin; erl```
- ```l(fibonacci_pcr). l(pcr_utils).``` (you can also load sum_pows_pcr instead of fibonacci_pcr depending on the example you want to run)
- Generate a test PCR: ``` Pcr = fibonacci_pcr:generate_pcr().``` or ``` Pcr = sum_pows_pcr:generate_pcr().``` depending on what you loaded
- Send an input to the PCR (in this case the input is 5): ``` pcr_utils:send_input_to_pcr(5, Pcr).```
- Flush the process mailbox in order to see the PCR output for the input that has been sent: ``` flush().```
- You should be able to see something like: ``` Shell got {pcr_output,2} ```, which is the output that the current process (the shell) received from the PCR.

## Architecture
### Objective
The idea of this project is to implement a way to write PCRs taking advantage of the way Erlang manages concurrency. Erlang allows us to create as many processes as we need, to manage every concurrent activity. A concurrenct activity is not the same as a concurrent task. For example, in this project we have tasks such as producing, consuming and reducing items, but a real concurrent activity would be processing a specific item (i.e. applying some of those tasks to a particular item). This is an important idea that will be applied many times in this project.

## Concepts
### Components
These are represented by records and can be found [here](https://github.com/german94/pcr-erlang/blob/master/src/pcr_components.erl) and [here](https://github.com/german94/pcr-erlang/blob/master/src/pcr_nodes.erl). They have data associated such as an ID and some helper functions such as getters (like get_id/1 and constructors like create_pcr/3).

  * _**producer**_: has an ID which is just a name to identify it and a node_logic. A node_logic is basically a lambda function containing the logic that executes the producer.
  * _**consumer**_: has an ID, a list of sources and a node_logic. The list of sources is basically a list of IDs. The semantics of this sources list works as follows: if there are n sources, then consumer logic will be executed taking n parameters, each one from the corresponding source.
  * _**reducer**_: has an ID, a list of sources, a node_logic and an initial value.
  * _**pcr**_: has a producer, a list of consumers and a reducer. The producer and the consumers may be nested PCRs, however this kind of composition has not been implemented yet.
  * _**active_node**_: has an ID that matches to a PCR's component (which can be one of the above mentioned) and the pid of the process running its node_logic. It represents a _living_ component.
  * _**listener**_: this concept has not a type associated, but it's implicitly used in many parts. Basically if we have two components `A` and `B` that are part of the same PCR, `A` is a listener of `B` if `id(B)` is an element of `sources(A)`.
  
 ### Tokens
We use two kind of tokens, both of them generated using [this](https://github.com/german94/pcr-erlang/blob/master/src/pcr_utils.erl#L51) function
 #### External token
 #### Internal token
 
 ### Behavior
 
 #### Consume
The consume logic can be found [here](https://github.com/german94/pcr-erlang/blob/master/src/pcr_consume.erl). It's important to remark that this is used for both **consuming** and **producing**. That's because, in the end, the consume logic is just some function _applied_ to an item, in the case of producing items, we'll be applying the _produce_ function to a range of numbers (from 0 to the input that was entered to the PCR), so it's just a particular way of consumption.
The consumption of an item is accomplished by first doing some setup like receiving the inputs from its sources and receiving its listeners. The first ones are needed so the consumption function can be applied effectively to all the parameters, the last ones are used to send the processed item to the nodes that need it.

#### Reduce
The reduce logic can be found [here](https://github.com/german94/pcr-erlang/blob/master/src/pcr_reduce.erl). The first thing that is done when the reduce process starts is to create a _**reduction**_. A reduction is a record that contains all the data related to a reduction of a particular input that came to the PCR. It has the following fields:
* reduced: the reducer component that is being used
* reduced_value: current value associated to the reduction
* number_of_items_to_reduce: the amount of elements between 0 and the number that went into the PCR
* params_from_sources: a map with internal tokens as keys and tuples composed of source ID and source value.
* token: external token
* output_pid: the PID of the process that will receive the full reduction which will be the PCR's output

The reduce_loop function takes this reduction and updates it (creating a new one) every time it receives an input from one of the sources. The loop checks if all the sources have sent their inputs and if that's the case, it will perform the reduction as it has all the needed information and send the processed item to the output. If there's some source that have not sent it's proessed input yet, then the reducer will block in the receive statement, waiting for that data.

#### Output handler
