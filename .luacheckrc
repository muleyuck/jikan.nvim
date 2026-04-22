---@diagnostic disable: lowercase-global
max_comment_line_length = false
codes = true

ignore = {
	"212", -- Unused argument
	"631", -- Line is too long
	"122", -- Setting a readonly global
	"542", -- Check empty if branch
}

-- Exclude test fixtures and generated files
exclude_files = {
	"tests/",
}

read_globals = {
	"vim",
}
