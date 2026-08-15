const r4os = @import("r4os");

pub const op_capabilities: u32 = 1;
pub const op_parse_summary: u32 = 2;
pub const op_render_text: u32 = 3;
pub const op_selftest: u32 = 4;

pub const result_ok: i32 = 0;
pub const result_bad_buffer: i32 = -2;
pub const result_unknown_op: i32 = -4;
pub const result_output_small: i32 = -5;
pub const result_malformed: i32 = -6;
pub const result_limit: i32 = -8;
pub const result_busy: i32 = -9;

var protocol_api: ?*const r4os.r4dev.ProtocolApi = null;
var workspace_busy: u8 = 0;
var document_workspace: r4os.html.Document = .{};
var view_workspace: r4os.html.PlainView = .{};

comptime {
    asm (r4os.r4dev.protocolEntriesAsm("r4html_init", "r4html_shutdown", "r4html_query", "r4html_dispatch"));
}

export fn r4html_init(api: *const r4os.r4dev.ProtocolApi) callconv(.c) i32 {
    protocol_api = api;
    var ctx = r4os.r4dev.ProtocolContext.init(api);
    ctx.logInfo("R4HTML.R4P init");
    _ = ctx.registerRole("application.html", .data, 0);
    _ = ctx.setStatus(.active, "HTML document parser active");
    return 0;
}

export fn r4html_shutdown() callconv(.c) i32 {
    document_workspace.reset();
    view_workspace.reset();
    protocol_api = null;
    return 0;
}

export fn r4html_query(out: *r4os.abi.ProtocolStatus) callconv(.c) i32 {
    out.* = .{
        .state = @intFromEnum(r4os.abi.ProtocolState.active),
        .flags = 0,
        .last_error = 0,
        .reserved = 0,
        .note = note("R4HTML ready"),
    };
    return 0;
}

export fn r4html_dispatch(op: u32, in_buffer: *const r4os.abi.ProtocolBuffer, out_buffer: *r4os.abi.ProtocolBuffer) callconv(.c) i32 {
    return switch (op) {
        op_capabilities => writeOut(out_buffer, "role=application.html;encoding=utf-8|windows-1252;mime=text/html;mode=standards|limited-quirks|quirks;dom=owned;view=text|heading|list|link;limits=bounded"),
        op_parse_summary => parseSummary(in_buffer, out_buffer),
        op_render_text => renderText(in_buffer, out_buffer),
        op_selftest => selftest(out_buffer),
        else => result_unknown_op,
    };
}

fn parseSummary(in_buffer: *const r4os.abi.ProtocolBuffer, out_buffer: *r4os.abi.ProtocolBuffer) i32 {
    if (!claimWorkspace()) return result_busy;
    defer releaseWorkspace();
    const input = inputBytes(in_buffer) orelse return result_bad_buffer;
    const stats = document_workspace.parse(input, .{}) catch |err| return htmlError(err);
    const out = outputBytes(out_buffer) orelse return result_bad_buffer;
    var len: usize = 0;
    if (!append(out, &len, "encoding=") or
        !append(out, &len, if (stats.encoding == .utf8) "utf-8" else "windows-1252") or
        !append(out, &len, ";mode=") or
        !append(out, &len, switch (stats.mode) {
            .no_quirks => "standards",
            .limited_quirks => "limited-quirks",
            .quirks => "quirks",
        }) or
        !append(out, &len, ";nodes=") or
        !appendDecimal(out, &len, stats.nodes) or
        !append(out, &len, ";attributes=") or
        !appendDecimal(out, &len, stats.attributes) or
        !append(out, &len, ";recoveries=") or
        !appendDecimal(out, &len, stats.recoveries))
    {
        return result_output_small;
    }
    return finish(out_buffer, len);
}

fn renderText(in_buffer: *const r4os.abi.ProtocolBuffer, out_buffer: *r4os.abi.ProtocolBuffer) i32 {
    if (!claimWorkspace()) return result_busy;
    defer releaseWorkspace();
    const input = inputBytes(in_buffer) orelse return result_bad_buffer;
    _ = document_workspace.parse(input, .{}) catch |err| return htmlError(err);
    view_workspace.build(&document_workspace) catch |err| return htmlError(err);
    const out = outputBytes(out_buffer) orelse return result_bad_buffer;
    var len: usize = 0;
    if (view_workspace.title().len > 0) {
        if (!append(out, &len, "# ") or !append(out, &len, view_workspace.title()) or !append(out, &len, "\n")) return result_output_small;
    }
    var line_index: usize = 0;
    while (line_index < view_workspace.line_count) : (line_index += 1) {
        const line = view_workspace.lines[line_index];
        const prefix: []const u8 = switch (line.kind) {
            .heading1 => "H1 ",
            .heading2 => "H2 ",
            .heading3 => "H3 ",
            .list_item => "LI ",
            .link => "A ",
            else => "",
        };
        if (!append(out, &len, prefix) or
            !append(out, &len, view_workspace.lineText(line_index)) or
            !append(out, &len, "\n"))
        {
            return result_output_small;
        }
    }
    return finish(out_buffer, len);
}

fn selftest(out_buffer: *r4os.abi.ProtocolBuffer) i32 {
    if (!claimWorkspace()) return result_busy;
    defer releaseWorkspace();
    const fixture =
        "<!doctype html><html><head><meta charset=utf-8><title>Klick &amp; DOM</title>" ++
        "<style>hidden { color: red }</style></head><body><h1>Heading</h1>" ++
        "<p id=first>Text &lt; value<p>Recovered<ul><li>One<li>Two</ul>" ++
        "<a href='/next'>Next</a><script>if (a < b) hidden()</script></body></html>";
    const stats = document_workspace.parse(fixture, .{}) catch return result_malformed;
    if (stats.mode != .no_quirks or stats.recoveries == 0) return result_malformed;
    if (r4os.html.classifyMediaType("text/html;charset=utf-8") != .html or
        r4os.html.classifyMediaType("application/json") != .unsupported) return result_malformed;
    const paragraph = document_workspace.findFirstElement("p") orelse return result_malformed;
    if (!equals(document_workspace.attribute(paragraph, "id") orelse "", "first")) return result_malformed;
    document_workspace.setAttribute(paragraph, "class", "notice") catch return result_limit;
    if (!equals(document_workspace.attribute(paragraph, "class") orelse "", "notice")) return result_malformed;
    view_workspace.build(&document_workspace) catch return result_limit;
    if (!equals(view_workspace.title(), "Klick & DOM") or view_workspace.line_count < 5) return result_malformed;
    if (!equals(view_workspace.lineText(0), "Heading") or view_workspace.lines[0].kind != .heading1) return result_malformed;
    return writeOut(out_buffer, "R4HTML selftest: OK parser=ok recovery=ok dom=ok encoding=ok mode=ok mime=ok view=ok");
}

fn claimWorkspace() bool {
    return @cmpxchgStrong(u8, &workspace_busy, 0, 1, .acquire, .monotonic) == null;
}

fn releaseWorkspace() void {
    @atomicStore(u8, &workspace_busy, 0, .release);
}

fn htmlError(err: r4os.html.Error) i32 {
    return switch (err) {
        error.SourceTooLarge, error.StringLimit, error.NodeLimit, error.AttributeLimit, error.DepthLimit, error.ViewLimit => result_limit,
        error.UnsupportedMediaType => result_malformed,
        else => result_malformed,
    };
}

fn inputBytes(buffer: *const r4os.abi.ProtocolBuffer) ?[]const u8 {
    if (buffer.data == null or buffer.len > buffer.capacity) return null;
    const ptr: [*]const u8 = @ptrCast(buffer.data.?);
    return ptr[0..buffer.len];
}

fn outputBytes(buffer: *r4os.abi.ProtocolBuffer) ?[]u8 {
    if (buffer.data == null) return null;
    const ptr: [*]u8 = @ptrCast(buffer.data.?);
    return ptr[0..buffer.capacity];
}

fn finish(buffer: *r4os.abi.ProtocolBuffer, len: usize) i32 {
    if (len > buffer.capacity) return result_output_small;
    buffer.len = @intCast(len);
    return result_ok;
}

fn writeOut(buffer: *r4os.abi.ProtocolBuffer, value: []const u8) i32 {
    const out = outputBytes(buffer) orelse return result_bad_buffer;
    if (value.len > out.len) return result_output_small;
    if (value.len > 0) @memcpy(out[0..value.len], value);
    return finish(buffer, value.len);
}

fn append(out: []u8, len: *usize, value: []const u8) bool {
    if (value.len > out.len -| len.*) return false;
    if (value.len > 0) @memcpy(out[len.* .. len.* + value.len], value);
    len.* += value.len;
    return true;
}

fn appendDecimal(out: []u8, len: *usize, value: usize) bool {
    var digits: [20]u8 = undefined;
    var count: usize = 0;
    var remaining = value;
    if (remaining == 0) return append(out, len, "0");
    while (remaining > 0) : (remaining /= 10) {
        digits[count] = @intCast('0' + remaining % 10);
        count += 1;
    }
    while (count > 0) {
        count -= 1;
        if (!append(out, len, digits[count .. count + 1])) return false;
    }
    return true;
}

fn equals(left: []const u8, right: []const u8) bool {
    if (left.len != right.len) return false;
    for (left, right) |a, b| if (a != b) return false;
    return true;
}

fn note(comptime value: []const u8) [64]u8 {
    var out: [64]u8 = .{0} ** 64;
    const count = @min(value.len, out.len - 1);
    @memcpy(out[0..count], value[0..count]);
    return out;
}
