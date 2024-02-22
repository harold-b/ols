package server

import "core:fmt"
import "core:log"
import "core:odin/ast"

import "src:common"

get_inlay_hints :: proc(
	document: ^Document,
	symbols: map[uintptr]SymbolAndNode,
) -> (
	[]InlayHint,
	bool,
) {
	hints := make([dynamic]InlayHint, context.temp_allocator)

	ast_context := make_ast_context(
		document.ast,
		document.imports,
		document.package_name,
		document.uri.uri,
		document.fullpath,
	)

	Visit_Data :: struct {
		calls: [dynamic]^ast.Node,
	}

	data := Visit_Data {
		calls = make([dynamic]^ast.Node, context.temp_allocator),
	}

	visit :: proc(visitor: ^ast.Visitor, node: ^ast.Node) -> ^ast.Visitor {
		if node == nil || visitor == nil {
			return nil
		}

		data := cast(^Visit_Data)visitor.data

		if call, ok := node.derived.(^ast.Call_Expr); ok {
			append(&data.calls, node)
		}

		return visitor
	}

	visitor := ast.Visitor {
		data  = &data,
		visit = visit,
	}

	for decl in document.ast.decls {
		ast.walk(&visitor, decl)
	}


	loop: for node_call in &data.calls {
		symbol_arg_count := 0
		is_selector_call := false

		call := node_call.derived.(^ast.Call_Expr)

		for arg in call.args {
			if _, ok := arg.derived.(^ast.Field_Value); ok {
				continue loop
			}
		}

		if selector, ok := call.expr.derived.(^ast.Selector_Expr);
		   ok && selector.op.kind == .Arrow_Right {
			is_selector_call = true
		}

		if symbol_and_node, ok := symbols[cast(uintptr)node_call]; ok {
			if symbol_call, ok := symbol_and_node.symbol.value.(SymbolProcedureValue);
			   ok {
				for arg, i in symbol_call.arg_types {
					if i == 0 && is_selector_call {
						continue
					}

					for name in arg.names {
						if symbol_arg_count >= len(call.args) {
							continue loop
						}

						label := ""
						is_ellipsis := false

						if arg.type != nil {
							if ellipsis, ok := arg.type.derived.(^ast.Ellipsis);
							   ok {
								is_ellipsis = true
							}
						}

						#partial switch v in name.derived {
						case ^ast.Ident:
							label = v.name
						case ^ast.Poly_Type:
							if ident, ok := v.type.derived.(^ast.Ident); ok {
								label = ident.name
							} else {
								continue loop
							}
						case:
							continue loop
						}

						range := common.get_token_range(
							call.args[symbol_arg_count],
							string(document.text),
						)
						hint := InlayHint {
							kind     = .Parameter,
							label    = fmt.tprintf("%v = ", label),
							position = range.start,
						}
						append(&hints, hint)

						symbol_arg_count += 1

						if is_ellipsis {
							continue loop
						}
					}

				}
			}
		}
	}

	return hints[:], true
}
