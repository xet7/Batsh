open Core.Std
open Winbat_ast

module BAST = Batsh_ast
module Symbol_table = Batsh.Symbol_table

let rec compile_leftvalue
    (lvalue: BAST.leftvalue)
    ~(symtable: Symbol_table.t)
    ~(scope: Symbol_table.Scope.t)
  : leftvalue =
  match lvalue with
  | BAST.Identifier ident ->
    Identifier ident
  | BAST.ListAccess (lvalue, index) ->
    let lvalue = compile_leftvalue lvalue ~symtable ~scope in
    let index = compile_expression_to_varint index ~symtable ~scope in
    ListAccess (lvalue, index)

and compile_expression_to_varint
    (expr : BAST.expression)
    ~(symtable : Symbol_table.t)
    ~(scope : Symbol_table.Scope.t)
  : varint =
  match expr with
  | BAST.Leftvalue lvalue ->
    Var (compile_leftvalue lvalue ~symtable ~scope)
  | BAST.Int num ->
    Integer num
  | _ ->
    failwith "Index should be either var or int"

let rec compile_expression_to_arith
    (expr : BAST.expression)
    ~(symtable : Symbol_table.t)
    ~(scope : Symbol_table.Scope.t)
  : arithmetic =
  match expr with
  | BAST.Bool false ->
    Int 0
  | BAST.Bool true ->
    Int 1
  | BAST.Int num ->
    Int num
  | BAST.Leftvalue lvalue ->
    Leftvalue (compile_leftvalue lvalue ~symtable ~scope)
  | BAST.ArithUnary (operator, expr) ->
    ArithUnary (operator, compile_expression_to_arith expr ~symtable ~scope)
  | BAST.ArithBinary (operator, left, right) ->
    ArithBinary (operator,
                 compile_expression_to_arith left ~symtable ~scope,
                 compile_expression_to_arith right ~symtable ~scope)
  | BAST.String _
  | BAST.Float _
  | BAST.List _
  | BAST.Concat _
  | BAST.StrCompare _
  | BAST.Call _ ->
    failwith "Can not be here"

let rec compile_expression
    (expr : BAST.expression)
    ~(symtable : Symbol_table.t)
    ~(scope : Symbol_table.Scope.t)
  : varstrings =
  match expr with
  | BAST.Bool false ->
    [String "0"]
  | BAST.Bool true ->
    [String "1"]
  | BAST.Int num ->
    [String (string_of_int num)]
  | BAST.String str ->
    [String str]
  | BAST.Leftvalue lvalue ->
    [Variable (compile_leftvalue lvalue ~symtable ~scope)]
  | BAST.Concat (left, right) ->
    let left = compile_expression left ~symtable ~scope in
    let right = compile_expression right ~symtable ~scope in
    left @ right
  | BAST.Call _ ->
    failwith "Not implemented: get stdout of given command"
  | _ ->
    assert false (* TODO *)

let compile_expressions
    (exprs : BAST.expressions)
    ~(symtable : Symbol_table.t)
    ~(scope : Symbol_table.Scope.t)
  : varstrings =
  List.concat (List.map exprs ~f: (compile_expression ~symtable ~scope))

let rec compile_expression_statement
    (expr : BAST.expression)
    ~(symtable : Symbol_table.t)
    ~(scope : Symbol_table.Scope.t)
  : statement =
  match expr with
  | BAST.Call (ident, exprs) ->
    Call (String ident, compile_expressions exprs ~symtable ~scope)
  | _ ->
    assert false (* TODO *)

let rec compile_statement
    (stmt : BAST.statement)
    ~(symtable : Symbol_table.t)
    ~(scope : Symbol_table.Scope.t)
  : statements =
  match stmt with
  | BAST.Comment comment ->
    [Comment comment]
  | BAST.Block stmts ->
    compile_statements stmts ~symtable ~scope
  | BAST.Expression expr ->
    [compile_expression_statement expr ~symtable ~scope]
  | BAST.Assignment (lvalue, expr) ->
    compile_assignment lvalue expr ~symtable ~scope
  | BAST.If _
  | BAST.IfElse _
  | BAST.While _
  | BAST.Global _
  | BAST.Empty ->
    []

and compile_assignment
    (lvalue : BAST.leftvalue)
    (expr : BAST.expression)
    ~(symtable : Symbol_table.t)
    ~(scope : Symbol_table.Scope.t)
  : statements =
  match expr with
  | BAST.String _
  | BAST.StrCompare _
  | BAST.Concat _
  | BAST.Call _
  | BAST.Leftvalue _ ->
    let lvalue = compile_leftvalue lvalue ~symtable ~scope in
    [Assignment (lvalue, compile_expression expr ~symtable ~scope)]
  | BAST.Bool _
  | BAST.Int _
  | BAST.Float _
  | BAST.ArithUnary _
  | BAST.ArithBinary _ ->
    let lvalue = compile_leftvalue lvalue ~symtable ~scope in
    [ArithAssign (lvalue, compile_expression_to_arith expr ~symtable ~scope)]
  | BAST.List exprs ->
    List.concat (List.mapi exprs ~f: (fun i expr ->
        compile_assignment (BAST.ListAccess (lvalue, (BAST.Int i))) expr ~symtable ~scope
      ))

and compile_statements
    (stmts: BAST.statements)
    ~(symtable: Symbol_table.t)
    ~(scope: Symbol_table.Scope.t)
  :statements =
  List.fold stmts ~init: [] ~f: (fun acc stmt ->
      let stmts = compile_statement stmt ~symtable ~scope in
      acc @ stmts
    )

let compile_function
    (name, params, stmts)
    ~(symtable : Symbol_table.t)
  : statements =
  (* let scope = Symbol_table.scope symtable name in *)
  (* let body = compile_statements stmts ~symtable ~scope in *)
  [] (* TODO implement function *)

let compile_toplevel
    ~(symtable : Symbol_table.t)
    (topl: BAST.toplevel)
  : statements =
  match topl with
  | BAST.Statement stmt ->
    compile_statement stmt ~symtable
      ~scope: (Symbol_table.global_scope symtable)
  | BAST.Function func ->
    compile_function func ~symtable

let compile (batsh: Batsh.t) : t =
  let program = Batsh.split_ast batsh
      ~split_string: true
      ~split_list_literal: true
      ~split_call: true
      ~split_string_compare: true
      ~split_arithmetic: true
  in
  let symtable = Batsh.symtable batsh in
  let stmts = List.fold program ~init: [] ~f: (fun acc topl ->
      let stmts = compile_toplevel topl ~symtable in
      acc @ stmts
    ) in
  (Raw "@echo off")
  :: (Raw "setlocal EnableDelayedExpansion")
  :: (Raw "setlocal EnableExtensions")
  :: stmts
