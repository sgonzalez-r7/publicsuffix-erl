-module(tld_generator).

-export([generate/0,
         generate/2
        ]).


-define(TMPFILE, "publicsuffix.dat").


%%% HERE BE DRAGONS

%%% API functions

generate() ->
    generate(url, "https://publicsuffix.org/list/public_suffix_list.dat").


generate(url, Url) ->
    io:setopts([{encoding, unicode}]),
    inets:start(),
    application:start(asn1),
    application:start(crypto),
    application:start(public_key),
    application:start(ssl),
    Req = httpc:request(Url),
    case Req of
        {ok, Result} ->
            {_, _, Body} = Result,
            file:write_file(?TMPFILE, Body),
            generate(file, ?TMPFILE);
        Error ->
            Error
    end;

generate(file, File) ->
    io:setopts([{encoding, unicode}]),
    {ok, Data} = file:read_file(File),
    Lines = [strip(Line) || Line <- binary:split(Data, <<"\n">>, [global])],
    FilterMap = fun
        (<<"//", _/binary>>) -> false;
        (<<>>) -> false;
        (Line) -> {true, {binary:split(Line, <<".">>, [global]), Line}}
    end,
    Props = sort_props(lists:filtermap(FilterMap, Lines)),
    head(),
    {Exceptions, Rules} = lists:partition(fun ({_S, <<"!", _/binary>>}) -> true; (_) -> false end, Props),
    lists:map(fun({SplittedLine, Line}) ->
        Match = bin_fmt(lists:reverse(SplittedLine)),
        io:format("tld([~ts = H | _R]) -> [H, ~ts];~n", [Match, p(skip_to_dot(Line))])
    end, Exceptions),
    lists:map(fun({SplittedLine, Line}) ->
        Match = bin_fmt(lists:reverse(SplittedLine)),
        io:format("tld([~ts | [H | _T]]) -> [H, ~ts];~n", [Match, p(Line)])
    end, Rules),
    io:format("tld(_) -> undefined.~n").


%%% Internal functions


strip(<<$\s, Rest/binary>>) -> strip(Rest);
strip(Bin) -> Bin.


sort_props(Props) ->
    SortFun = fun({A1, _}, {A2, _}) -> length(A1) > length(A2) end,
    lists:sort(SortFun, Props).


head() ->
    Mod = [
        "-module(tld).",
        "-export([domain/1, suffix/1]).",
        "",
        "-spec domain(T :: bitstring()) -> Domain :: bitstring().",
        "domain(T) ->",
        "   case parse(T) of",
        "       undefined -> undefined;",
        "       [H, Suffix] -> <<H/binary, \".\", Suffix/binary>>",
        "   end.",
        "",
        "-spec suffix(T :: bitstring()) -> Suffix :: bitstring().",
        "suffix(T) ->",
        "   case parse(T) of",
        "       undefined -> undefined;",
        "       [_, Suffix] -> Suffix",
        "   end.",
        "",
        "parse(S) ->",
        "   Host = case binary:split(S, <<\":\">>) of",
        "       [S] -> S;",
        "       [_Scheme, Tail] ->",
        "          Tokens = binary:split(Tail, <<\"/\">>, [global]),",
        "          lists:nth(3, Tokens)",
        "   end,",
        "   tld(lists:reverse(binary:split(Host, <<\".\">>, [global]))).",
        "\n"
    ],
    io:format(string:join(Mod, "\n")).


bin_fmt(L) -> bin_fmt(L, <<>>).

bin_fmt([<<"*">>], Acc) -> <<Acc/binary, "D1">>;
bin_fmt([<<"!", H/binary>>], Acc) -> <<Acc/binary, (p(H))/binary>>;
bin_fmt([H], Acc) -> <<Acc/binary, (p(H))/binary>>;
bin_fmt([H|T], Acc) -> bin_fmt(T, <<Acc/binary, (p(H))/binary, ", ">>).


p(<<"*", Rest/binary>>) -> unicode:characters_to_binary(io_lib:format("<<D1/binary, \"~ts\">>", [Rest]));
p(Binary) -> unicode:characters_to_binary(io_lib:format("~tp", [Binary])).

skip_to_dot(<<$., Rest/binary>>) -> Rest;
skip_to_dot(<<_C/utf8, Rest/binary>>) -> skip_to_dot(Rest).
