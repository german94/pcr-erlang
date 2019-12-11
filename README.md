# pcr-erlang
PCR pattern implementation in Erlang programming language

### How to run it
- Download Erlang from: https://www.erlang.org/
- Open a terminal in the directory that contains all the .erl files
- Type ```erl```
- Type ``` cover:compile_directory().``` to compile the code (don't forget the . at the end of each Erlang code line)
- Generate a test PCR: ``` Pcr = fibonacci_pcr:generate_fib_even_counter_pcr().```
- Send an input to the PCR (in this case the input is 5): ``` pcr:send_input_to_pcr(5, Pcr).```
- Flush the process mailbox in order to see the PCR output for the input that has been sent: ``` flush().```
- You should be able to see something like: ``` Shell got {pcr_output,2} ```, which is the output that the current process (the shell) received from the PCR.
