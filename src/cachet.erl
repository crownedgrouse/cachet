%%%-------------------------------------------------------------------
%%% File:      cachet.erl
%%% @author    Eric Pailleau <cachet@crownedgrouse.com>
%%% @copyright 2014 crownedgrouse.com
%%% @doc  
%%% Cachet listener for Mnesia events
%%% @end  
%%%
%%% Permission to use, copy, modify, and/or distribute this software
%%% for any purpose with or without fee is hereby granted, provided
%%% that the above copyright notice and this permission notice appear
%%% in all copies.
%%%
%%% THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL
%%% WARRANTIES WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED
%%% WARRANTIES OF MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE
%%% AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT, INDIRECT, OR
%%% CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM
%%% LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT,
%%% NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF OR IN
%%% CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
%%%
%%% Created : 2014-11-10
%%%-------------------------------------------------------------------
-module(cachet).
-behaviour(gen_server).

-export([start_link/1]).
-export([init/1, handle_call/3, handle_cast/2,stop/0]).

%%-------------------------------------------------------------------------
%% @doc 
%% @end
%%-------------------------------------------------------------------------
start_link(S) ->
    gen_server:start_link({local, cachet}, cachet, [S], []).

%%-------------------------------------------------------------------------
%% @doc 
%% @end
%%-------------------------------------------------------------------------
init([S]) ->

    % Add gen_fsm child to supervisor for each table pair
    case application:get_env(tables) of
         undefined    -> ignore, {error, "!"} ;
         {ok, Tables} -> gen_server:cast(cachet, {add_childs, S, Tables}),
                         {ok, Tables}    
    end.

%%-------------------------------------------------------------------------
%% @doc 
%% @end
%%-------------------------------------------------------------------------
handle_call(_, _From, State) ->
    {reply, State, State}.

%%-------------------------------------------------------------------------
%% @doc 
%% @end
%%-------------------------------------------------------------------------
handle_cast({add_childs, S, Tables}, State) ->
     Fun = fun({R, D, C, M, O}) ->  case supervisor:start_child(S, {R
                                                                  ,{cachet_fsm, start_link, [{R, D, C, M, O}]}
                                                                  ,permanent, brutal_kill, worker
                                                                  ,[cachet_fsm]}) of
                                        {error, _Err}   -> {R, D, C, M, O};
                                        {ok, Child}     -> {R, D, C, M, O, Child};
                                        {ok, Child, _}  -> {R, D, C, M, O, Child}
                                   end
    end,
    State2 = lists:map(Fun, Tables),
    {noreply, State2}.

%%-------------------------------------------------------------------------
%% @doc 
%% @end
%%-------------------------------------------------------------------------
stop() -> ok.



