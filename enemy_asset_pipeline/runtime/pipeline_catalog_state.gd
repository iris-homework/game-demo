@static_unload
extends RefCounted
## Plain session data lives apart from the catalog's static method bytecode.
## Keep this holder free of catalog/script references so the ownership graph
## can release naturally, even while the populated cache survives until exit.

static var preview_path_override: String = ""
static var published_path_override: String = ""
static var _cache: Dictionary = {}
static var _diagnostics: Array[String] = []
static var _revision := 0
static var _source_signature := ""
