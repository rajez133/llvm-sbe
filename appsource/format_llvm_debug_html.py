#!/usr/bin/env python3
"""
Format LLVM debug output as HTML with syntax highlighting and TOC sidebar.
- Captures ALL compilation stages (LLVM IR and Machine IR)
- Shows exact line-level diff between each consecutive stage
- Generates TWO output files:
    <input>_formatted.html       — unified diff view (added/removed inline)
    <input>_sidebyside.html      — side-by-side diff (previous | current)
- Provides clickable Table of Contents sidebar in both outputs
"""

import sys
import re
from difflib import SequenceMatcher
from typing import List, Tuple, Optional
import html as html_mod

# ---------------------------------------------------------------------------
# Stage extraction
# ---------------------------------------------------------------------------
HEADER_RE = re.compile(
    r'^(?:# )?\*\*\* IR Dump After (.+) \(([^)]+)\) \*\*\*:?$'
)


def extract_stages(lines: List[str]) -> List[Tuple[str, str, str, List[str]]]:
    """Returns list of (raw_header, pass_name, pass_id, content_lines)."""
    stages: List[Tuple[str, str, str, List[str]]] = []
    current_header: Optional[str] = None
    current_pass_name = ""
    current_pass_id = ""
    current_content: List[str] = []

    for raw in lines:
        line = raw.rstrip('\n')
        m = HEADER_RE.match(line.strip()) or HEADER_RE.match(line)
        if m:
            if current_header is not None:
                stages.append((current_header, current_pass_name,
                                current_pass_id, current_content))
            current_header = line.strip()
            current_pass_name = m.group(1).strip()
            current_pass_id = m.group(2).strip()
            current_content = []
        elif current_header is not None:
            current_content.append(line.rstrip())

    if current_header is not None:
        stages.append((current_header, current_pass_name,
                       current_pass_id, current_content))
    return stages


# ---------------------------------------------------------------------------
# Content normalisation
# ---------------------------------------------------------------------------

# Matches the slot-index prefix that slotindexes pass adds:
#   "16B\t  instruction"  →  strip "16B\t" leaving "  instruction"
#   "0B\tbb.0.entry:"     →  strip "0B\t"  leaving "bb.0.entry:"
#   "\t  successors:"     →  strip leading "\t" leaving "  successors:"
_SLOT_INDEX_RE = re.compile(r'^\d+B\t')
_TAB_INDENT_RE = re.compile(r'^\t([ ;])')


def _strip_slot_index(line: str) -> str:
    """Remove slot-index prefix so indexed and non-indexed lines compare equal."""
    m = _SLOT_INDEX_RE.match(line)
    if m:
        return line[m.end():]          # "16B\t  LIS 5" → "  LIS 5"
    m = _TAB_INDENT_RE.match(line)
    if m:
        return line[1:]                # "\t  successors:" → "  successors:"
    return line


def normalise_content(content: List[str]) -> List[str]:
    first = next((l for l in content if l.strip()), "")
    is_machine = (first.startswith('# Machine code') or
                  any(l.strip().startswith('bb.') for l in content[:8]))
    result = []
    for line in content:
        s = line.strip()
        if not s:
            continue
        if is_machine:
            if s.startswith('# Machine code for') or s.startswith('# End machine code'):
                continue
            result.append(_strip_slot_index(line))
        else:
            if (s.startswith('; ModuleID') or
                    s.startswith('source_filename') or
                    s.startswith('target datalayout') or
                    s.startswith('target triple') or
                    s.startswith('attributes #') or
                    re.match(r'^![\w]+ = ', s) or
                    re.match(r'^!\d+ = ', s) or
                    s.startswith('!llvm.')):
                continue
            result.append(line)
    return result


# ---------------------------------------------------------------------------
# Unified diff  →  flat annotated list
# ---------------------------------------------------------------------------
# Each item: ('added'|'removed'|'unchanged', line_text)

def compute_unified_diff(
    prev: List[str], curr: List[str]
) -> Tuple[List[Tuple[str, str]], int]:
    if not prev:
        return [('unchanged', l) for l in curr], 0
    if not curr:
        return [], 0

    result: List[Tuple[str, str]] = []
    change_count = 0
    for tag, i1, i2, j1, j2 in SequenceMatcher(None, prev, curr,
                                                autojunk=False).get_opcodes():
        if tag == 'equal':
            for line in prev[i1:i2]:
                result.append(('unchanged', line))
        elif tag == 'replace':
            for line in prev[i1:i2]:
                result.append(('removed', line)); change_count += 1
            for line in curr[j1:j2]:
                result.append(('added', line)); change_count += 1
        elif tag == 'delete':
            for line in prev[i1:i2]:
                result.append(('removed', line)); change_count += 1
        elif tag == 'insert':
            for line in curr[j1:j2]:
                result.append(('added', line)); change_count += 1
    return result, change_count


# ---------------------------------------------------------------------------
# Side-by-side diff  →  list of row pairs
# ---------------------------------------------------------------------------
# Each row: (left_cls, left_text, right_cls, right_text)
#   cls: 'added' | 'removed' | 'unchanged' | 'empty'

SbsRow = Tuple[str, str, str, str]


def compute_sbs_diff(
    prev: List[str], curr: List[str]
) -> Tuple[List[SbsRow], int]:
    """
    Produce side-by-side row pairs.
    - equal   → (unchanged, line, unchanged, line)
    - replace → pair each old line with its new counterpart; pad shorter side
    - delete  → (removed, line, empty, '')
    - insert  → (empty, '', added, line)
    Returns (rows, change_count).
    """
    if not prev:
        # First stage: nothing on the left
        rows = [('empty', '', 'unchanged', l) for l in curr]
        return rows, 0
    if not curr:
        return [], 0

    rows: List[SbsRow] = []
    change_count = 0

    for tag, i1, i2, j1, j2 in SequenceMatcher(None, prev, curr,
                                                autojunk=False).get_opcodes():
        if tag == 'equal':
            for line in prev[i1:i2]:
                rows.append(('unchanged', line, 'unchanged', line))
        elif tag == 'replace':
            old_lines = prev[i1:i2]
            new_lines = curr[j1:j2]
            change_count += len(old_lines) + len(new_lines)
            for k in range(max(len(old_lines), len(new_lines))):
                l = old_lines[k] if k < len(old_lines) else ''
                r = new_lines[k] if k < len(new_lines) else ''
                lc = 'removed' if k < len(old_lines) else 'empty'
                rc = 'added'   if k < len(new_lines) else 'empty'
                rows.append((lc, l, rc, r))
        elif tag == 'delete':
            for line in prev[i1:i2]:
                rows.append(('removed', line, 'empty', ''))
                change_count += 1
        elif tag == 'insert':
            for line in curr[j1:j2]:
                rows.append(('empty', '', 'added', line))
                change_count += 1

    return rows, change_count


# ---------------------------------------------------------------------------
# Shared HTML helpers
# ---------------------------------------------------------------------------
def _stage_header_html(pass_name: str, pass_id: str,
                       stage_num: int, total_stages: int,
                       change_count: int) -> str:
    safe_name = html_mod.escape(pass_name)
    safe_id   = html_mod.escape(pass_id)
    badge = (f'<span class="change-badge">&#9650; {change_count} changes</span>'
             if change_count > 0 else
             '<span class="no-change-badge">no changes</span>')
    return (f'<div class="stage-header" id="stage-{stage_num}">'
            f'<div class="stage-title">STAGE {stage_num}/{total_stages}: '
            f'{safe_name} {badge}</div>'
            f'<div class="pass-id">Pass: {safe_id}</div>'
            f'</div>')


def _generate_toc(stage_info: List[Tuple[str, str, int]]) -> str:
    items = []
    for idx, (pass_name, _pid, change_count) in enumerate(stage_info, 1):
        safe_name = html_mod.escape(pass_name)
        if change_count > 0:
            badge    = f'<span class="toc-badge toc-badge-changed">{change_count}</span>'
            item_cls = 'toc-item-changed'
        else:
            badge    = '<span class="toc-badge toc-badge-unchanged">&#10003;</span>'
            item_cls = 'toc-item-unchanged'
        items.append(
            f'<a href="#stage-{idx}" class="toc-item {item_cls}">'
            f'<span class="toc-number">{idx}</span>'
            f'<span class="toc-name">{safe_name}</span>'
            f'{badge}</a>')
    return '\n'.join(items)


# ---------------------------------------------------------------------------
# UNIFIED HTML template + renderer
# ---------------------------------------------------------------------------
_UNIFIED_CSS = '''\
*{margin:0;padding:0;box-sizing:border-box;}
body{font-family:'Consolas','Monaco','Courier New',monospace;background:#1e1e1e;
     color:#d4d4d4;font-size:13px;line-height:1.5;display:flex;height:100vh;overflow:hidden;}
.sidebar{width:300px;background:#252526;border-right:1px solid #3e3e42;
         overflow-y:auto;flex-shrink:0;}
.sidebar-header{background:#1e3a5f;padding:16px;position:sticky;top:0;z-index:10;
                border-bottom:2px solid #4fc3f7;}
.sidebar-title{font-size:15px;font-weight:bold;color:#ffd700;margin-bottom:4px;}
.sidebar-subtitle{font-size:11px;color:#81d4fa;}
.toc-item{display:flex;align-items:center;padding:8px 12px;text-decoration:none;
          color:#d4d4d4;border-left:3px solid transparent;gap:6px;}
.toc-item:hover{background:#2d2d30;border-left-color:#4fc3f7;}
.toc-item-changed{background:#1a2a1a;}
.toc-item-unchanged{opacity:0.55;}
.toc-number{width:36px;color:#858585;font-size:11px;flex-shrink:0;}
.toc-name{flex:1;font-size:11px;word-break:break-word;}
.toc-badge{display:inline-block;padding:1px 6px;border-radius:8px;font-size:10px;
           font-weight:bold;flex-shrink:0;}
.toc-badge-changed{background:#4ec9b0;color:#000;}
.toc-badge-unchanged{background:#3e3e42;color:#858585;}
.main-content{flex:1;overflow-y:auto;padding:20px;}
h1{color:#4fc3f7;text-align:center;padding:16px;background:#252526;
   border-radius:6px;margin-bottom:20px;font-size:18px;}
.summary{background:#2d2d30;padding:12px;border-radius:4px;margin-bottom:14px;
         border-left:4px solid #4fc3f7;}
.legend{background:#2d2d30;padding:12px;border-radius:4px;margin-bottom:20px;
        border-left:4px solid #ffd700;display:flex;gap:24px;flex-wrap:wrap;}
.legend-item{display:flex;align-items:center;gap:8px;font-size:12px;}
.swatch{display:inline-block;width:14px;height:14px;border-radius:2px;}
.stage-header{background:#1e3a5f;border-left:4px solid #4fc3f7;padding:12px 16px;
              margin:28px 0 8px 0;border-radius:4px;scroll-margin-top:20px;}
.stage-title{font-size:15px;font-weight:bold;color:#ffd700;margin-bottom:3px;}
.pass-id{font-size:11px;color:#81d4fa;font-style:italic;}
.change-badge{display:inline-block;background:#4ec9b0;color:#000;padding:2px 8px;
              border-radius:10px;font-size:11px;font-weight:bold;margin-left:8px;}
.no-change-badge{display:inline-block;background:#3e3e42;color:#858585;padding:2px 8px;
                 border-radius:10px;font-size:11px;margin-left:8px;}
.code-block{background:#252526;border:1px solid #3e3e42;border-radius:4px;
            padding:10px 14px;margin:6px 0 0 0;overflow-x:auto;}
.code-line{white-space:pre;display:block;padding:1px 0 1px 4px;
           border-left:3px solid transparent;}
.unchanged{color:#808080;}
.added{background:#143020;color:#4ec9b0;border-left-color:#4ec9b0;}
.added::before{content:"+ ";color:#4ec9b0;font-weight:bold;}
.removed{background:#3a1010;color:#f48771;border-left-color:#f48771;
         text-decoration:line-through;opacity:0.85;}
.removed::before{content:"- ";color:#f48771;font-weight:bold;}
'''

_UNIFIED_TEMPLATE = '''\
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>LLVM Compilation Stages — Unified Diff</title>
<style>{css}</style>
</head>
<body>
<div class="sidebar">
  <div class="sidebar-header">
    <div class="sidebar-title">&#9776; Compilation Stages</div>
    <div class="sidebar-subtitle">{total_stages} passes &nbsp;|&nbsp; {changed_stages} with changes</div>
  </div>
  {toc}
</div>
<div class="main-content">
  <h1>LLVM Compilation Stages &mdash; PPE42 Backend &mdash; Unified Diff</h1>
  <div class="summary">
    <strong>Total stages:</strong> {total_stages} &nbsp;
    <strong>Stages with changes:</strong> {changed_stages} &nbsp;
    <strong>Source:</strong> {source_file}
  </div>
  <div class="legend">
    <div class="legend-item">
      <span class="swatch" style="background:#808080;"></span>
      <span style="color:#808080;">Unchanged</span>
    </div>
    <div class="legend-item">
      <span class="swatch" style="background:#4ec9b0;"></span>
      <span style="color:#4ec9b0;">Added / new</span>
    </div>
    <div class="legend-item">
      <span class="swatch" style="background:#f48771;"></span>
      <span style="color:#f48771;">Removed / old</span>
    </div>
  </div>
  {content}
</div>
</body>
</html>
'''


def render_unified(
    stage_info: List[Tuple[str, str, int]],
    annotated:  List[Tuple[List[Tuple[str, str]], int]],
    source_file: str,
) -> str:
    toc_html = _generate_toc(stage_info)
    changed_stages = sum(1 for _, _, c in stage_info if c > 0)
    parts: List[str] = []

    for idx, ((pass_name, pass_id, change_count), (diff_lines, _)) in \
            enumerate(zip(stage_info, annotated), 1):
        parts.append(_stage_header_html(pass_name, pass_id,
                                        idx, len(stage_info), change_count))
        parts.append('<div class="code-block">')
        if not diff_lines:
            parts.append('<div class="code-line unchanged">(empty stage)</div>')
        for cls, line in diff_lines:
            parts.append(f'<div class="code-line {cls}">{html_mod.escape(line)}</div>')
        parts.append('</div>')

    return _UNIFIED_TEMPLATE.format(
        css=_UNIFIED_CSS,
        total_stages=len(stage_info),
        changed_stages=changed_stages,
        source_file=html_mod.escape(source_file),
        toc=toc_html,
        content='\n'.join(parts),
    )


# ---------------------------------------------------------------------------
# SIDE-BY-SIDE HTML template + renderer
# ---------------------------------------------------------------------------
_SBS_CSS = '''\
*{margin:0;padding:0;box-sizing:border-box;}
body{font-family:'Consolas','Monaco','Courier New',monospace;background:#1e1e1e;
     color:#d4d4d4;font-size:13px;line-height:1.5;display:flex;height:100vh;overflow:hidden;}
.sidebar{width:280px;background:#252526;border-right:1px solid #3e3e42;
         overflow-y:auto;flex-shrink:0;}
.sidebar-header{background:#1e3a5f;padding:16px;position:sticky;top:0;z-index:10;
                border-bottom:2px solid #4fc3f7;}
.sidebar-title{font-size:15px;font-weight:bold;color:#ffd700;margin-bottom:4px;}
.sidebar-subtitle{font-size:11px;color:#81d4fa;}
.toc-item{display:flex;align-items:center;padding:8px 12px;text-decoration:none;
          color:#d4d4d4;border-left:3px solid transparent;gap:6px;}
.toc-item:hover{background:#2d2d30;border-left-color:#4fc3f7;}
.toc-item-changed{background:#1a2a1a;}
.toc-item-unchanged{opacity:0.55;}
.toc-number{width:36px;color:#858585;font-size:11px;flex-shrink:0;}
.toc-name{flex:1;font-size:11px;word-break:break-word;}
.toc-badge{display:inline-block;padding:1px 6px;border-radius:8px;font-size:10px;
           font-weight:bold;flex-shrink:0;}
.toc-badge-changed{background:#4ec9b0;color:#000;}
.toc-badge-unchanged{background:#3e3e42;color:#858585;}
.main-content{flex:1;overflow-y:auto;padding:20px;}
h1{color:#4fc3f7;text-align:center;padding:16px;background:#252526;
   border-radius:6px;margin-bottom:20px;font-size:18px;}
.summary{background:#2d2d30;padding:12px;border-radius:4px;margin-bottom:14px;
         border-left:4px solid #4fc3f7;}
.legend{background:#2d2d30;padding:12px;border-radius:4px;margin-bottom:20px;
        border-left:4px solid #ffd700;display:flex;gap:24px;flex-wrap:wrap;}
.legend-item{display:flex;align-items:center;gap:8px;font-size:12px;}
.swatch{display:inline-block;width:14px;height:14px;border-radius:2px;}
.stage-header{background:#1e3a5f;border-left:4px solid #4fc3f7;padding:12px 16px;
              margin:28px 0 8px 0;border-radius:4px;scroll-margin-top:20px;}
.stage-title{font-size:15px;font-weight:bold;color:#ffd700;margin-bottom:3px;}
.pass-id{font-size:11px;color:#81d4fa;font-style:italic;}
.change-badge{display:inline-block;background:#4ec9b0;color:#000;padding:2px 8px;
              border-radius:10px;font-size:11px;font-weight:bold;margin-left:8px;}
.no-change-badge{display:inline-block;background:#3e3e42;color:#858585;padding:2px 8px;
                 border-radius:10px;font-size:11px;margin-left:8px;}
/* diff table */
.diff-table{width:100%;border-collapse:collapse;margin:6px 0 0 0;
            border:1px solid #3e3e42;border-radius:4px;overflow:hidden;}
.diff-table .col-header{background:#2a2a2e;color:#81d4fa;font-size:11px;
                        padding:5px 10px;text-align:left;border-bottom:1px solid #3e3e42;
                        font-weight:bold;letter-spacing:0.05em;width:50%;}
.diff-table .col-header.right{border-left:1px solid #3e3e42;}
.diff-table td{white-space:pre;padding:1px 10px 1px 6px;vertical-align:top;
               border-left:3px solid transparent;font-size:13px;}
.diff-table td.right{border-left:1px solid #2a2a2e;}
.diff-table tr.row-unchanged td{color:#808080;background:#252526;}
.diff-table tr.row-changed td.cell-removed{background:#3a1010;color:#f48771;
                                           border-left-color:#f48771;}
.diff-table tr.row-changed td.cell-added{background:#143020;color:#4ec9b0;
                                         border-left-color:#4ec9b0;}
.diff-table tr.row-changed td.cell-removed::before{content:"- ";font-weight:bold;}
.diff-table tr.row-changed td.cell-added::before{content:"+ ";font-weight:bold;}
.diff-table tr.row-changed td.cell-empty{background:#1e1e1e;color:#3e3e42;}
.diff-table tr.row-insert td.cell-added{background:#143020;color:#4ec9b0;
                                        border-left-color:#4ec9b0;}
.diff-table tr.row-insert td.cell-added::before{content:"+ ";font-weight:bold;}
.diff-table tr.row-insert td.cell-empty{background:#1e1e1e;}
.diff-table tr.row-delete td.cell-removed{background:#3a1010;color:#f48771;
                                          border-left-color:#f48771;
                                          text-decoration:line-through;opacity:0.85;}
.diff-table tr.row-delete td.cell-removed::before{content:"- ";font-weight:bold;}
.diff-table tr.row-delete td.cell-empty{background:#1e1e1e;}
'''

_SBS_TEMPLATE = '''\
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>LLVM Compilation Stages — Side-by-Side Diff</title>
<style>{css}</style>
</head>
<body>
<div class="sidebar">
  <div class="sidebar-header">
    <div class="sidebar-title">&#9776; Compilation Stages</div>
    <div class="sidebar-subtitle">{total_stages} passes &nbsp;|&nbsp; {changed_stages} with changes</div>
  </div>
  {toc}
</div>
<div class="main-content">
  <h1>LLVM Compilation Stages &mdash; PPE42 Backend &mdash; Side-by-Side Diff</h1>
  <div class="summary">
    <strong>Total stages:</strong> {total_stages} &nbsp;
    <strong>Stages with changes:</strong> {changed_stages} &nbsp;
    <strong>Source:</strong> {source_file}
  </div>
  <div class="legend">
    <div class="legend-item">
      <span class="swatch" style="background:#808080;"></span>
      <span style="color:#808080;">Unchanged</span>
    </div>
    <div class="legend-item">
      <span class="swatch" style="background:#f48771;"></span>
      <span style="color:#f48771;">Previous (removed)</span>
    </div>
    <div class="legend-item">
      <span class="swatch" style="background:#4ec9b0;"></span>
      <span style="color:#4ec9b0;">Current (added)</span>
    </div>
  </div>
  {content}
</div>
</body>
</html>
'''


def _row_html(lc: str, lt: str, rc: str, rt: str) -> str:
    """Render one side-by-side table row."""
    # determine overall row class
    if lc == 'unchanged':
        row_cls = 'row-unchanged'
    elif lc == 'removed' and rc == 'added':
        row_cls = 'row-changed'
    elif lc == 'removed':
        row_cls = 'row-delete'
    elif rc == 'added':
        row_cls = 'row-insert'
    else:
        row_cls = 'row-unchanged'

    left_cls  = f'cell-{lc}'   # cell-removed / cell-unchanged / cell-empty
    right_cls = f'cell-{rc}'   # cell-added   / cell-unchanged / cell-empty

    return (f'<tr class="{row_cls}">'
            f'<td class="{left_cls}">{html_mod.escape(lt)}</td>'
            f'<td class="right {right_cls}">{html_mod.escape(rt)}</td>'
            f'</tr>')


def render_sidebyside(
    stage_info:   List[Tuple[str, str, int]],
    sbs_annotated: List[Tuple[List[SbsRow], int]],
    source_file: str,
    prev_names:  List[str],   # pass_name of the previous stage for each stage
) -> str:
    toc_html = _generate_toc(stage_info)
    changed_stages = sum(1 for _, _, c in stage_info if c > 0)
    parts: List[str] = []

    for idx, ((pass_name, pass_id, change_count), (rows, _), prev_name) in \
            enumerate(zip(stage_info, sbs_annotated, prev_names), 1):
        parts.append(_stage_header_html(pass_name, pass_id,
                                        idx, len(stage_info), change_count))
        parts.append('<table class="diff-table">')
        # column headers — left = previous stage name, right = current
        safe_prev = html_mod.escape(prev_name) if prev_name else '(first stage)'
        safe_curr = html_mod.escape(pass_name)
        parts.append(
            f'<tr>'
            f'<th class="col-header">&#9664; Previous: {safe_prev}</th>'
            f'<th class="col-header right">&#9654; Current: {safe_curr}</th>'
            f'</tr>')
        if not rows:
            parts.append(
                '<tr class="row-unchanged">'
                '<td class="cell-empty"></td>'
                '<td class="right cell-empty">(empty stage)</td>'
                '</tr>')
        for lc, lt, rc, rt in rows:
            parts.append(_row_html(lc, lt, rc, rt))
        parts.append('</table>')

    return _SBS_TEMPLATE.format(
        css=_SBS_CSS,
        total_stages=len(stage_info),
        changed_stages=changed_stages,
        source_file=html_mod.escape(source_file),
        toc=toc_html,
        content='\n'.join(parts),
    )


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <llc-debug-all-passes.txt>")
        sys.exit(1)

    input_file  = sys.argv[1]
    base        = input_file.replace('.txt', '') if input_file.endswith('.txt') else input_file
    out_unified = base + '_formatted.html'
    out_sbs     = base + '_sidebyside.html'

    print(f"Reading {input_file}...")
    with open(input_file, 'r', errors='replace') as f:
        lines = f.readlines()

    stages = extract_stages(lines)
    print(f"Found {len(stages)} compilation stages")

    if not stages:
        print("ERROR: No stages found.")
        sys.exit(1)

    # Compute both diff variants in one pass
    stage_info:    List[Tuple[str, str, int]] = []
    uni_annotated: List[Tuple[List[Tuple[str, str]], int]] = []
    sbs_annotated: List[Tuple[List[SbsRow], int]] = []
    prev_names:    List[str] = []   # name of previous stage (for SbS header)

    prev_norm: List[str] = []
    prev_name: str = ''

    for raw_hdr, pass_name, pass_id, content in stages:
        curr_norm = normalise_content(content)

        uni_diff, change_count = compute_unified_diff(prev_norm, curr_norm)
        sbs_diff, _            = compute_sbs_diff(prev_norm, curr_norm)

        stage_info.append((pass_name, pass_id, change_count))
        uni_annotated.append((uni_diff, change_count))
        sbs_annotated.append((sbs_diff, change_count))
        prev_names.append(prev_name)

        prev_norm = curr_norm
        prev_name = pass_name

    changed_stages = sum(1 for _, _, c in stage_info if c > 0)

    # Write unified
    print(f"Writing unified diff → {out_unified}")
    with open(out_unified, 'w') as f:
        f.write(render_unified(annotated=uni_annotated,
                               stage_info=stage_info,
                               source_file=input_file))

    # Write side-by-side
    print(f"Writing side-by-side diff → {out_sbs}")
    with open(out_sbs, 'w') as f:
        f.write(render_sidebyside(stage_info=stage_info,
                                  sbs_annotated=sbs_annotated,
                                  source_file=input_file,
                                  prev_names=prev_names))

    print(f"\nDone! {len(stages)} stages, {changed_stages} with changes.")
    print(f"  Unified:      {out_unified}")
    print(f"  Side-by-side: {out_sbs}")


if __name__ == '__main__':
    main()

# Made with Bob
