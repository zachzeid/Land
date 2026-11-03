extends RefCounted
## SafeExec - OS.execute without a shell's say
## On macOS Godot passes OS.execute arguments through the shell inside double quotes, where $, `,
## \ and " still act: `$(...)` in an argument runs. Player speech and generated text reach these
## calls (memory queries, image prompts), so every argument is checked or cleaned first

const UNSAFE = ["$", "`", "\\", "\""]

static func is_safe(arg) -> bool:
	var text = str(arg)
	for c in UNSAFE:
		if c in text:
			return false
	return true

## Free text (an image prompt): drop the characters a shell would act on
static func clean(text: String) -> String:
	for c in UNSAFE:
		text = text.replace(c, "")
	return text

## OS.execute, refusing (-1, nothing run) when any argument is unsafe
static func execute(path: String, args: Array, output: Array = [], read_stderr: bool = true) -> int:
	for arg in args:
		if not is_safe(arg):
			push_error("[SafeExec] Refused to run %s: an argument holds a shell character" % path.get_file())
			return -1
	return OS.execute(path, args, output, read_stderr)

## OS.execute_with_pipe under the same check: {} (nothing run) when any argument is unsafe
## Text written to the process's stdin never passes through a shell, so only the arguments matter
static func execute_with_pipe(path: String, args: Array, blocking: bool = true) -> Dictionary:
	for arg in args:
		if not is_safe(arg):
			push_error("[SafeExec] Refused to run %s: an argument holds a shell character" % path.get_file())
			return {}
	return OS.execute_with_pipe(path, args, blocking)
