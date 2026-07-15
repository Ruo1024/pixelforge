class_name PFGenerationPromptBuilder
extends RefCounted

## One prompt composition path shared by developer preview and Provider requests.


static func build(prefix: String, prompt: String, subject: String = "") -> String:
	var parts: Array[String] = []
	for value in [prefix, prompt, subject]:
		var normalized := String(value).strip_edges()
		if not normalized.is_empty():
			parts.append(normalized)
	return ", ".join(parts)
