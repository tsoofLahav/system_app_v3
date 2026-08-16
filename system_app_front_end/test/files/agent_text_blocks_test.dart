import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/files/model/agent_text_blocks.dart';

void main() {
  test('headings, paragraphs and blank runs keep their line numbers', () {
    const text = '## Goals\n\nFirst line.\nSecond line.';
    final blocks = parseAgentTextBlocks(text);

    expect(blocks.length, 4);
    final heading = blocks[0] as AgentHeadingBlock;
    expect(heading.level, 2);
    expect(heading.text, 'Goals');
    expect(heading.lineStart, 0);
    expect((blocks[1] as AgentSpacerBlock).count, 1);
    expect((blocks[2] as AgentParagraphBlock).text, 'First line.');
    expect((blocks[3] as AgentParagraphBlock).lineStart, 3);
  });

  test('explicit spacer marker carries its count', () {
    final blocks = parseAgentTextBlocks('A\n[SPACER n="3"]\nB');
    expect((blocks[1] as AgentSpacerBlock).count, 3);
  });

  test('task list splits active and done and numbers every task line', () {
    const text = '[TASK_LIST id="42"]\n'
        'ACTIVE:\n'
        '- [ ] Call clinic\n'
        'DONE:\n'
        '- [x] Book room\n'
        '[/TASK_LIST]';
    final block = parseAgentTextBlocks(text).single as AgentTaskListBlock;

    expect(block.objectId, 42);
    expect(block.lineStart, 0);
    expect(block.lineEnd, 5);
    expect(block.tasks.map((t) => t.title), ['Call clinic', 'Book room']);
    expect(block.tasks.map((t) => t.done), [false, true]);
    // The second task sits on line 4 — a hunk there marks only that task.
    expect(block.tasks[1].line, 4);
  });

  test('info takes the first line as title, keeps body lines addressable', () {
    const text = '[INFO id="17"]\nLens notes\nPractice daily.\nTrack weekly.\n[/INFO]';
    final block = parseAgentTextBlocks(text).single as AgentInfoBlock;

    expect(block.title, 'Lens notes');
    expect(block.titleLine, 1);
    expect(block.bodyLines.map((l) => l.text), ['Practice daily.', 'Track weekly.']);
    expect(block.bodyLines.last.line, 3);
  });

  test('single-line info stays body only', () {
    final block =
        parseAgentTextBlocks('[INFO id="9"]\nJust a note\n[/INFO]').single
            as AgentInfoBlock;
    expect(block.title, '');
    expect(block.titleLine, -1);
    expect(block.bodyLines.single.text, 'Just a note');
  });

  test('table rows split on visible tab and each row knows its line', () {
    const text = '[TABLE id="11"]\nHeader A\\tHeader B\nValue 1\\tValue 2\n[/TABLE]';
    final block = parseAgentTextBlocks(text).single as AgentTableBlock;

    expect(block.objectId, 11);
    expect(block.columnCount, 2);
    expect(block.rows[1].cells, ['Value 1', 'Value 2']);
    expect(block.rows[1].line, 2);
  });

  test('escaped backslash-t stays inside the cell', () {
    expect(splitAgentRow(r'a\\tb\tc'), ['a\tb', 'c']);
    expect(splitAgentRow(r'plain'), ['plain']);
  });

  test('graph keeps labels, values and colours with their lines', () {
    const text = '[GRAPH id="8" chartType="bar"]\n'
        'Week1\\tWeek2\n'
        '10\\t20\n'
        '#4A90D9\\t#E07A5F\n'
        '[/GRAPH]';
    final block = parseAgentTextBlocks(text).single as AgentGraphBlock;

    expect(block.chartType, 'bar');
    expect(block.labels, ['Week1', 'Week2']);
    expect(block.values, ['10', '20']);
    expect(block.colors, ['#4A90D9', '#E07A5F']);
    expect(block.valuesLine, 2);
    expect(block.colorsLine, 3);
  });

  test('lists number themselves and keep nesting', () {
    const text = '[BULLET_LIST]\n- One\n  - Nested\n[/BULLET_LIST]\n'
        '[ORDERED_LIST]\n1. Step one\n2. Step two\n[/ORDERED_LIST]';
    final blocks = parseAgentTextBlocks(text);

    final bullets = blocks[0] as AgentListBlock;
    expect(bullets.ordered, isFalse);
    expect(bullets.items[1].indent, 1);
    expect(bullets.items[1].marker, '•');

    final ordered = blocks[1] as AgentListBlock;
    expect(ordered.ordered, isTrue);
    expect(ordered.items.map((i) => i.marker), ['1.', '2.']);
    expect(ordered.items[1].line, 6);
  });

  test('image marker reads caption and url', () {
    final block = parseAgentTextBlocks(
      '[IMAGE id="5" caption="Shot" url="/uploads/shot.png"]',
    ).single as AgentImageBlock;

    expect(block.objectId, 5);
    expect(block.caption, 'Shot');
    expect(block.url, '/uploads/shot.png');
  });

  test('an unclosed fence still ends at the last line', () {
    final block =
        parseAgentTextBlocks('[TABLE id="3"]\na\\tb').single as AgentTableBlock;
    expect(block.lineEnd, 1);
    expect(block.rows.single.cells, ['a', 'b']);
  });

  test('dash lines with no fence around them still read as a list', () {
    // What a broken write leaves behind: the marker lost its `[`, the items
    // stayed. The reader should see a list, never marker language.
    const text = 'Plan:\nBULLET_LIST]\n- one\n- two\nAfter.';
    final blocks = parseAgentTextBlocks(text);

    expect((blocks[0] as AgentParagraphBlock).text, 'Plan:');
    final residue = blocks[1] as AgentUnknownBlock;
    expect(residue.isMarker, isTrue);
    final list = blocks[2] as AgentListBlock;
    expect(list.items.map((i) => i.text), ['one', 'two']);
    expect(list.items.first.line, 2);
    expect(list.lineEnd, 3);
    expect((blocks[3] as AgentParagraphBlock).text, 'After.');
  });

  test('a stray or attributed marker is flagged, plain brackets are not', () {
    for (final line in ['[/BULLET_LIST]', '[BULLET_LIST id="3"]', 'TABLE]']) {
      final block = parseAgentTextBlocks(line).single;
      expect(
        (block as AgentUnknownBlock).isMarker,
        isTrue,
        reason: 'expected $line to be treated as a marker',
      );
    }
    expect(
      parseAgentTextBlocks('a line with [IMPORTANT] in it').single,
      isA<AgentParagraphBlock>(),
    );
  });

  test('numbered lines outside a fence keep their own numbering', () {
    final list = parseAgentTextBlocks('1. one\n2. two').single as AgentListBlock;
    expect(list.ordered, isTrue);
    expect(list.items.map((i) => i.marker), ['1.', '2.']);
  });

  test('every block line maps back into the source lines', () {
    const text = '## Title\n\n[TASK_LIST id="1"]\nACTIVE:\n- [ ] x\n[/TASK_LIST]\nTail';
    final lines = text.split('\n');
    for (final block in parseAgentTextBlocks(text)) {
      expect(block.lineStart, inInclusiveRange(0, lines.length - 1));
      expect(block.lineEnd, inInclusiveRange(block.lineStart, lines.length - 1));
    }
  });
}
