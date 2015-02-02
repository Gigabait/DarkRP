local CompileString = CompileString
local debug = debug
local error = error
local error = error
local file = file
local hook = hook
local isfunction = isfunction
local os = os
local pcall = pcall
local string = string
local table = table
local tonumber = tonumber
local unpack = unpack

-- Template for syntax errors
local synErrTranslation = [[Lua is unable to understand file "%s" because its author made a mistake around line number %i.
The best help I can give you is this:

%s

Hints:
%s

------]]

-- Template for runtime errors
local runErrTranslation = [[A runtime error has occurred in "%s" on line %i.
The best help I can give you is this:

%s

Hints:
%s

The responsibility for this error lies with (the authors of) one (or more) of these files:
%s
------]]

-- Structure that contains syntax errors and their translations. Catches only the most common errors.
-- Order is important: the structure with the first match is taken.
local synErrs = {
    {
        match = "'=' expected near '(.*)'",
        text = "Right before the '%s', Lua expected to read an '='-sign, but it didn't.",
        format = function(m) return m[1] end,
        hints = {
            "Did you simply forget the '='-sign?",
            "Did you forget a comma?",
            "Is this supposed to be a local variable?"
        }
    },
    {
        match = "'.' expected [(]to close '([{[(])' at line ([0-9]+)[)] near '(.*)'",
        text = "There is an opening '%s' bracket at line %i, but this bracket is never closed or not closed in time. It was expected to be closed before the '%s' at line %i.",
        format = function(m, l) return m[1], m[2], m[3], l end,
        hints = {
            "Did you forget a comma?",
            "All open brackets ({, (, [) must have a matching closing bracket. Are you sure it's there?",
            "Brackets must be opened and closed in the right order. This will work: ({}), but this won't: ({)}."
        }
    },
    {
        match = "'end' expected [(]to close '(.*)' at line ([0-9]+)[)] near '(.*)'",
        text = "An '%s' was started on line %i, but it was never ended or not ended in time. It was expected to be ended before the '%s' at line %i",
        format = function(m, l) return m[1], m[2], m[3], l end,
        hints = {
            "For every if/for/do/while/function there must be an 'end' that closes it."
        }
    },
    {
        match = "unfinished string near '(.*)'",
        text = "The string '%s' at line %i is opened, but not closed.",
        format = function(m, l) return m[1], l end,
        hints = {
            "A string is a different word for literal text.",
            "Strings must be in single or double quotation marks (e.g. 'example', \"example\")",
            "A third option for strings is for them to be in double square brackets.",
            "Whatever you use (quotations or square brackets), you must not forget that strings are enclosed within a pair of quotation marks/square brackets."
        }
    },
    {
        match = "unfinished long string near '(.*)'",
        text = "Lua expected to see the end of a multiline string somewhere before the '%s' at line %i.",
        format = function(m, l) return m[1], l end,
        hints = {
            "A string is a different word for literal text.",
            "Multiline strings are strings that span over multiple lines.",
            "Multiline strings must be enclosed by double square brackets.",
            "Whatever you use (quotations or square brackets), you must not forget that strings are enclosed within a pair of quotation marks/square brackets.",
            "If you used brackets, the source of the mistake may be somewhere above the reported line."
        }
    },
    {
        match = "unfinished long comment near '(.*)'",
        text = "Lua expected to see the end of a multiline comment somewhere before the '%s' at line %i.",
        format = function(m, l) return m[1], l end,
        hints = {
            "A comment is text ignored by Lua.",
            "Multiline comments are ones that span multiple lines.",
            "Multiline comments must be enclosed by either /* and */ or double square brackets.",
            "Whatever you use (/**/ or square brackets), you must not forget that once you start a comment, you must end it.",
            "The source of the mistake may be somewhere above the reported line."
        }
    },
    -- Generic error messages
    {
        match = "function arguments expected near '(.*)'",
        text = "A function is being called right before '%s', but its arguments are not given.",
        format = function(m) return m[1] end,
        hints = {
            "Did you write 'something:otherthing'? Try changing it to 'something:otherthing()'"
        }
    },
    {
        match = "unexpected symbol near '(.*)'",
        text = "Right before the '%s', Lua encountered something it could not make sense of.",
        format = function(m) return m[1] end,
        hints = {"Did you forget something here? (Perhaps a closing bracket)", "Is it a typo?"}
    },
    {
        match = "'(.*)' expected near '(.*)'",
        text = "Right before the '%s', Lua expected to read a '%s', but it didn't.",
        format = function(m) return m[2], m[1] end,
        hints = {"Did you forget a keyword?", "Did you forget a comma?"}
    },
    {
        match = "malformed number near '(.*)'",
        text = "Lua attempted to read '%s' as a number, but failed to do so.",
        format = function(m) return m[1] end,
        hints = {
            "Numbers starting with '0x' are hexidecimal.",
            "Lua can get confused when doing '<number>..\"some text\"'. Try inserting a space between the number and the '..'."
        }
    },
}

-- Similar structure for runtime errors. Catches only the most common errors.
-- Order is important: the structure with the first match is taken
local runErrs = {
    {
        match = "table index is nil",
        text = "A table is being indexed by something that does not exist (table index is nil).", -- Requires improvement
        format = function() end,
        hints = {
            "The thing between square brackets does not exist (is nil)."
        }
    },
    {
        match = "table index is NaN",
        text = "A table is being indexed by something that is not really a number (table index is NaN).",
        format = function() end,
        hints = {
            "Did you divide zero by zero thinking it would be funny?"
        }
    },
    {
        match = "attempt to index global '(.*)' [(]a nil value[)]",
        text = "'%s' is being indexed like it is a table, but in reality it does not exist (is nil).",
        format = function(m) return m[1] end,
        hints = {
            "You either have 'something.somethingElse', 'something<somethingElse>' or 'something:somethingElse(more)'. The 'something' here does not exist.",
            "The < and > in the above example should be replaced by square brackets. Due to a limitation in the GMod error system it is impossible to have square brackets in errors."
        }
    },
    {
        match = "attempt to index global '(.*)' [(]a (.*) value[)]",
        text = "'%s' is being indexed like it is a table, but in reality it is a %s value.",
        format = function(m) return m[1], m[2] end,
        hints = {
            "You either have 'something.somethingElse' or 'something:somethingElse(more)'. The 'something' here is not a table."
        }
    },
    {
        match = "attempt to index a nil value",
        text = "Something is being indexed like it is a table, but in reality does not exist (is nil).",
        format = function() end,
        hints = {
            "You either have 'something.somethingElse', 'something<somethingElse>' or 'something:somethingElse(more)'. The 'something' here does not exist.",
            "The < and > in the above example should be replaced by square brackets. Due to a limitation in the GMod error system it is impossible to have square brackets in errors."
        }
    },
    {
        match = "attempt to index a (.*) value",
        text = "Something is being indexed like it is a table, but in reality it is a %s value.",
        format = function(m) return m[1] end,
        hints = {
            "You either have 'something.somethingElse', 'something<somethingElse>' or 'something:somethingElse(more)'. The 'something' here is not a table.",
            "The < and > in the above example should be replaced by square brackets. Due to a limitation in the GMod error system it is impossible to have square brackets in errors."
        }
    },
    {
        match = "attempt to call global '(.*)' [(]a nil value[)]",
        text = "'%s' is being called like it is a function, but in reality does not exist (is nil).",
        format = function(m) return m[1] end,
        hints = {
            "You are doing something(<otherstuff>). The 'something' here does not exist."
        }
    },
    {
        match = "attempt to call a nil value",
        text = "Something is being called like it is a function, but in reality it does not exist (is nil).",
        format = function() end,
        hints = {
            "You are doing something(<otherstuff>). The 'something' here does not exist."
        }
    },
    {
        match = "attempt to call global '(.*)' [(]a (.*) value[)]",
        text = "'%s' is being called like it is a function, but in reality it is a %s.",
        format = function(m) return m[1], m[2] end,
        hints = {
            "You are doing something(<otherstuff>). The 'something' here is not a function."
        }
    },
    {
        match = "attempt to call a (.*) value",
        text = "Something is being called like it is a function, but in reality it is a %s.",
        format = function(m) return m[1] end,
        hints = {
            "You are doing something(<otherstuff>). The 'something' here is not a function."
        }
    },
    {
        match = "attempt to call field '(.*)' [(]a nil value[)]",
        text = "'%s' is being called like it is a function, but in reality it does not exist (is nil).",
        format = function(m) return m[1] end,
        hints = {
            "You are doing either stuff.something(<otherstuff>) or stuff:something(<otherstuff>). The 'something' here does not exist."
        }
    },
    {
        match = "attempt to call field '(.*)' [(]a (.*) value[)]",
        text = "'%s' is being called like it is a function, but in reality it is a %s.",
        format = function(m) return m[1], m[2] end,
        hints = {
            "You are doing either stuff.something(<otherstuff>) or stuff:something(<otherstuff>). The 'something' here is not a function."
        }
    },
    {
        match = "attempt to concatenate global '(.*)' [(]a nil value[)]",
        text = "'%s' is being concatenated to something else, but '%s' does not exist (is nil).",
        format = function(m) return m[1], m[1] end,
        hints = {
            "Concatenation looks like this: something .. otherThing. Either something or otherThing does not exist."
        }
    },
    {
        match = "attempt to concatenate global '(.*)' [(]a (.*) value[)]",
        text = "'%s' is being concatenated to something else, but %s values cannot be concatenated.",
        format = function(m) return m[1], m[2] end,
        hints = {
            "Concatenation looks like this: something .. otherThing. Either something or otherThing is neither string nor number."
        }
    },
    {
        match = "attempt to concatenate a nil value",
        text = "Two (or more) things are being concatenated and one of them does not exist (is nil).",
        format = function() end,
        hints = {
            "Concatenation looks like this: something .. otherThing. Either something or otherThing does not exist."
        }
    },
    {
        match = "attempt to concatenate a (.*) value",
        text = "Two (or more) things are being concatenated and one of them is neither string nor number, but a %s.",
        format = function(m) return m[1] end,
        hints = {
            "Concatenation looks like this: something .. otherThing. Either something or otherThing is neither string nor number."
        }
    },
    {
        match = "stack overflow",
        text = "The stack of function calls has overflowed",
        format = function() end,
        hints = {
            "Most likely infinite recursion.",
            "Do you have a function calling itself?"
        }
    },
    {
        match = "attempt to compare two (.*) values",
        text = "A comparison is being made between two %s values. They cannot be compared.",
        format = function(m) return m[1] end,
        hints = {
            "This error usually occurs when two incompatible things are being compared.",
            "'comparison' in this context means one of <, >, <=, >= (smaller than, greater than, etc.)"
        }
    },
    {
        match = "attempt to compare (.*) with (.*)",
        text = "A comparison is being made between a %s and a %s. This is not possible.",
        format = function(m) return m[1], m[2] end,
        hints = {
            "This error usually occurs when two incompatible things are being compared.",
            "'Comparison' in this context means one of <, >, <=, >= (smaller than, greater than, etc.)"
        }
    },
    {
        match = "attempt to perform arithmetic on a (.*) value",
        text = "Arithmetic operations are being performed on a %s. This is not possible.",
        format = function(m) return m[1] end,
        hints = {
            "'Arithmetic' in this context means adding, multiplying, dividing, etc."
        }
    },
    {
        match = "attempt to get length of global '(.*)' [(]a nil value[)]",
        text = "The length of '%s' is requested as if it is a table, but in reality it does not exist (is nil).",
        format = function(m) return m[1] end,
        hints = {
            "You are doing #something. The 'something' here is does not exist."
        }
    },
    {
        match = "attempt to get length of global '(.*)' [(]a (.*) value[)]",
        text = "The length of '%s' is requested as if it is a table, but in reality it is a %s.",
        format = function(m) return m[1], m[2] end,
        hints = {
            "You are doing #something. The 'something' here is not a table."
        }
    },
    {
        match = "attempt to get length of a nil value",
        text = "The length of something is requested as if it is a table, but in reality it does not exist (is nil).",
        format = function(m) return m[1] end,
        hints = {
            "You are doing #something. The 'something' here is does not exist."
        }
    },
    {
        match = "attempt to get length of a (.*) value",
        text = "The length of something is requested as if it is a table, but in reality it is a %s.",
        format = function(m) return m[1] end,
        hints = {
            "You are doing #something. The 'something' here is not a table."
        }
    },
}

module("simplerr")

-- Translate the message of an error
local function translateMsg(msg, path, line, errs)
    local res
    local hints = {"No hints, sorry."}

    for i = 1, #errs do
        local trans = errs[i]

        if not string.find(msg, trans.match) then continue end

        -- translate <eof>
        msg = string.Replace(msg, "<eof>", "end of the file")

        res = string.format(trans.text, trans.format({string.match(msg, trans.match)}, line, path))
        hints = trans.hints

        break
    end

    return res or msg, "\t- " .. table.concat(hints, "\n\t- ")
end

-- Translate an error into a language understandable by non-programmers
local function translateError(path, err, translation, errs, stack)
    local line, msg = string.match(err, path .. ":([0-9]+): (.*)")
    line = tonumber(line)

    local msg, hints = translateMsg(msg, path, line, errs)
    local res = string.format(translation, path, line, msg, hints, stack)
    return res
end

-- Call a function and catch immediate runtime errors
function safeCall(f, ...)
    local res = {pcall(f, ...)}
    local succ, err = res[1], res[2]

    if succ then return unpack(res) end

    local path = debug.getinfo(f).short_src

    -- Investigate the stack
    local line = string.match(err, path .. ":([0-9]+)")
    local level, stack = 2, {string.format("\t1. %s on line %i", path, line)}

    while true do
        local info = debug.getinfo(level, "Sln")
        if not info then break end

        table.insert(stack, string.format("\t%i. %s on line %i", level, info.short_src, info.currentline))

        level = level + 1
    end

    return false, translateError(path, err, runErrTranslation, runErrs, table.concat(stack, '\n'))
end

-- Run a file or explain its syntax errors in layman's terms
-- Returns bool succeed, [string error]
-- Do NOT use this on clientside files.
-- Clientside files sent by the server cannot be read using file.Read unless you're the host of a listen server
function runFile(path)
    if not file.Exists(path, "LUA") then error(string.format("Could not run file '%s' (file not found)", path)) end
    local contents = file.Read(path, "LUA")
    local err = CompileString(contents, path, false)

    if isfunction(err) then return safeCall(err, path) end -- No syntax errors, check for immediate runtime errors

    return false, translateError(path, err, synErrTranslation, synErrs)
end

-- Error wrapper: decorator for runFile and safeCall that throws an error on failure.
-- Breaks execution. Must be the last decorator.
function wrapError(succ, err, ...)
    if succ then return succ, err, ... end

    error(err)
end

-- Hook wrapper: Calls a hook on error
function wrapHook(succ, err, ...)
    if not succ then hook.Call("onSimplerrError", nil, err) end

    return succ, err, ...
end

-- Logging wrapper: decorator for runFile and safeCall that logs failures.
local log = {}
function wrapLog(succ, err, ...)
    if succ then return succ, err, ... end

    local data = {
        err = err,
        time = os.time()
    }

    table.insert(log, data)

    return succ, err, ...
end

-- Retrieve the log
function getLog() return log end

-- Clear the log
function clearLog() log = {} end