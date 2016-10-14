# Transaction-and-Concurrency-Control

## Description
We consider a distributed systems with a server-client architecture, where the server controls a database (or a store) and the 
clients run some transactions on the database indirectly via communication with the server.
For the sake of simplicity we assume the following:

The store handles 4 global variables a, b, c and d
A transaction is a list of read and write operations of the form [{read, a}, {write, b, 200}, {read, d}, {write , c, 100}].
The processes (clients and servers) are supposed to run on different Erlang nodes. The clients are supposed to communicate 
with the server which is maintaining the store. The store is not visible to the clients. Only the server is visible. 
The clients are supposed to establish connection and then send transaction requests to the server, which in turn tells the
client whether the request was committed or aborted.

## Client Side Software
The client process provides a graphical interface in which the user can manually enter transactions. Internally, the 
client spawns a process handler. The handler starts a window and tries to establish a connection to the server by spawning 
a connector process. Once the connection is established, the user may enter a sequence of actions which will be collected by 
the handler. When the user enters the run command, the handler will send the transaction to the server and wait for a reply. 
The user will only get back the message abort or commit, and is then free to either run the transaction again or reset it 
and enter a new one.The modules that implement the client are in the files: client.erl, parser.erl and window.erl

## Server Side Software
The server receives message from the different clients and takes the proper actions towards the store. More precisely, 
the server spawns a registered process under the name transaction_server which does the following:

First it spawns a store process which maintains a list of variables [{a,0},{b,0},{c,0},{d,0}] (evaluating the function 
store_loop()).Then it evaluates the function server_loop() which is supposed to maintain connection to the clients and 
controls the store process.The module implementing the server is in the file server.erl.

## Starting the System
Download the following skeleton, extract it and compile it:
>tar xvfz project.tar.gz
>cd Project
>make

This will generate all the .beam files.
Now open different terminals and enter the directory where you compiled the skeleton (in each one of them).
In each terminal, start an Erlang node using the same cookie. For example:

### terminal 1
>erl -name client_1 -setcookie abc

### terminal 2
>erl -name client_2 -setcookie abc

### terminal 3
>erl -name server -setcookie abc

### Start a transaction server in terminal 3
>server:start().

Start 2 clients in the remaining terminals. Observe that in order to start the client you need to specify the name of the node where the transaction server is running. For example if it is running on the Erlang node 'server@machinename.it.uu.se', then start the clients as follows:

>client:start('server@machinename.it.uu.se').

It is not necessary that these applications are running on the same machine. For instance you can start the Erlang nodes on different machines. Below, we give an example of how you start a client on a remote machine:
Establish an ssh connection in terminal 1.
