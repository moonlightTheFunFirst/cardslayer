class_name FormulaEvaluator
extends RefCounted

const VARIABLES: Array[String] = ["base", "scaling", "strength", "wisdom", "agility", "luck", "max_hp", "max_mp"]
var tokens: Array[String] = []
var cursor: int = 0
var error: String = ""
var values: Dictionary = {}

func evaluate(source: String, inputs: Dictionary) -> Dictionary:
	if source.length() > 512:
		return {"ok": false, "error": "数式は512文字以内で指定してください"}
	tokens.clear()
	cursor = 0
	error = ""
	values = inputs
	var lexer := RegEx.new()
	lexer.compile("\\s*(?:(\\d+(?:\\.\\d+)?|[A-Za-z_][A-Za-z_0-9]*|[+*/()\\-]))")
	var offset: int = 0
	var clean := source.strip_edges()
	while offset < clean.length():
		var found := lexer.search(clean, offset)
		if found == null or found.get_start() != offset:
			return {"ok": false, "error": "許可されない数式構文: " + clean.substr(offset)}
		tokens.append(found.get_string(1))
		offset = found.get_end()
	if tokens.is_empty():
		return {"ok": false, "error": "数式が空です"}
	var result := expression()
	if cursor != tokens.size() and error.is_empty():
		error = "余分なトークン: " + tokens[cursor]
	if not is_finite(result):
		error = "数式結果が有限値ではありません"
	return {"ok": error.is_empty(), "value": result, "error": error}

func expression() -> float:
	var result := product()
	while cursor < tokens.size() and tokens[cursor] in ["+", "-"]:
		var op := tokens[cursor]
		cursor += 1
		var rhs := product()
		result = result + rhs if op == "+" else result - rhs
	return result

func product() -> float:
	var result := atom()
	while cursor < tokens.size() and tokens[cursor] in ["*", "/"]:
		var op := tokens[cursor]
		cursor += 1
		var rhs := atom()
		if op == "/" and rhs == 0.0:
			error = "ゼロ除算"
			return 0.0
		result = result * rhs if op == "*" else result / rhs
	return result

func atom() -> float:
	if cursor >= tokens.size():
		error = "値が必要です"
		return 0.0
	var token := tokens[cursor]
	cursor += 1
	if token == "-":
		return -atom()
	if token == "(":
		var result := expression()
		if cursor >= tokens.size() or tokens[cursor] != ")":
			error = "閉じ括弧が必要です"
		else:
			cursor += 1
		return result
	if token.is_valid_float():
		return token.to_float()
	if token in VARIABLES and values.has(token):
		return float(values[token])
	error = "未定義変数または不正な値: " + token
	return 0.0
