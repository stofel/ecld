
-module(ecld).

-export([get_pid/3, call/4, call/5, cast/4]).

-export([stop_cluster_by_domains_prefix/1]).

%% For debug only!!!
-export([list/1, list_all/1, len/1, len_all/1]). 



-type answer() :: {ok, pid()}|not_started|not_exists|{err, {atom(), binary()}}.
%%
%% Options = #{
%%    start => true, %% Start process if not exists
%%    init  => true  %% Init profile if not exists in database
%% }. 
%%  


-spec stop_cluster_by_domains_prefix(atom()) -> ok.
stop_cluster_by_domains_prefix(ClusterPrefix) when is_atom(ClusterPrefix) ->
  Prefix = atom_to_binary(ClusterPrefix, latin1),
  Len = size(Prefix),
  Sups = supervisor:which_children(ecld_sup),
  
  IsPrefix = fun(SName) -> 
    case atom_to_binary(SName, latin1) of 
      <<Prefix:Len/binary, _/binary>> -> true; 
      _ -> false 
    end 
  end,

  StopDomain = fun(SName) ->
    supervisor:terminate_child(ecld_sup, SName),
    supervisor:delete_child(ecld_sup, SName)
  end,

  [StopDomain(SName) || {SName, _, _,_} <- Sups, IsPrefix(SName)],
  ok;
stop_cluster_by_domains_prefix(_Clister) -> {err, wrong_claster_name}.


-spec get_pid(atom(), binary(), map()) -> answer().
get_pid(Cluster, Id, Options) ->
  case ecl:get(Cluster, Id) of
    {ok, {Status, [D]}} when Status == norma ->
      #{node := Node, name := Name} = D,
      gen_server:call({Name, Node}, {Status, D, Id, Options});
    {ok, {Status, Ds = [ND, _OD] }} when Status == proxy; Status == merge ->
      #{node := Node, name := Name} = ND,
      gen_server:call({Name, Node}, {Status, Ds, Id, Options});
    Else -> Else
  end.


call(Cluster, Id, Msg, Options) -> 
  case get_pid(Cluster, Id, Options) of
    {ok, Pid} -> gen_server:call(Pid, Msg);
    Else -> Else
  end.

call(Cluster, Id, Msg, Options, Timeout) -> 
  case get_pid(Cluster, Id, Options) of
    {ok, Pid} -> gen_server:call(Pid, Msg, Timeout);
    Else -> Else
  end.


cast(Cluster, Id, Msg, Options) ->
  case get_pid(Cluster, Id, Options) of
    {ok, Pid} -> gen_server:cast(Pid, Msg);
    Else -> Else
  end.



%%For debug only!!!
list(Cluster) ->
  CurNode = node(),
  case ecl:show(Cluster) of
    {ok,#{domains := Domains}} ->
      GetWorkersFun = fun
        (Fu, [{_, #{node := Node, name := Name}}|Dms], Acc = #{workers := Ws, 
                                                               errors := Errs}) when Node == CurNode -> 
            DomainMembersSupName = list_to_atom(atom_to_list(Name) ++ "_ms_sup"),
            case rpc:call(Node, supervisor, which_children, [DomainMembersSupName]) of
              List when is_list(List) -> Fu(Fu, Dms, Acc#{workers := [List|Ws]});
              _Else -> Fu(Fu, Dms, Acc#{errors := Errs + 1})
            end;
        (Fu, [_|Dms], Acc = #{errors := Errs}) ->
            Fu(Fu, Dms, Acc#{errors := Errs + 1});
        (_F, [], Acc = #{workers := Ws}) ->
            NewWs = lists:reverse(lists:flatten(Ws)),
            {ok, Acc#{workers := NewWs}} 
      end,
      GetWorkersFun(GetWorkersFun, Domains, #{workers => [], errors => 0});
    Else -> Else
  end.

%
list_all(Cluster) ->
  case ecl:show(Cluster) of
    {ok,#{domains := Domains}} ->
      GetWorkersFun = fun
        (Fu, [{_, #{node := Node, name := Name}}|Dms], Acc = #{workers := Ws, 
                                                               errors  := Errs,
                                                               nodes   := Nodes}) -> 
            DomainMembersSupName = list_to_atom(atom_to_list(Name) ++ "_ms_sup"),
            NewNodes = lists:usort([Node|Nodes]),
            case rpc:call(Node, supervisor, which_children, [DomainMembersSupName]) of
              List when is_list(List) -> 
                Fu(Fu, Dms, Acc#{workers := [List|Ws], nodes := NewNodes});
              _Else -> 
                Fu(Fu, Dms, Acc#{errors := Errs + 1, nodes := NewNodes})
            end;
        (Fu, [_|Dms], Acc = #{errors := Errs}) ->
            Fu(Fu, Dms, Acc#{errors := Errs + 1});
        (_F, [], Acc = #{workers := Ws}) ->
            NewWs = lists:reverse(lists:flatten(Ws)),
            {ok, Acc#{workers := NewWs}} 
      end,
      GetWorkersFun(GetWorkersFun, Domains, #{workers => [], errors => 0, nodes => []});
    Else -> Else
  end.

%
len(Cluster) ->
  case list(Cluster) of
    {ok, #{workers := Ws}} -> {ok, length(Ws)};
    Else -> Else
  end.

len_all(Cluster) ->
  case list_all(Cluster) of
    {ok, #{workers := Ws}} -> {ok, length(Ws)};
    Else -> Else
  end.
