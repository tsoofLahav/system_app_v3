import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/production_agent/agent_result_ui.dart';
import 'package:system_app_front_end/areas/production_agent/compact_undo_toast.dart';
import 'package:system_app_front_end/areas/production_agent/pending_review_ui.dart';
import 'package:system_app_front_end/core/l10n/app_strings.dart';


void main() {
  test('aiCanceling string is the waiting-to-drop copy', () {
    expect(AppStrings.en['aiCanceling'], 'Canceling the action…');
    expect(AppStrings.he['aiCanceling'], 'מבטל את הפעולה…');
  });

  test('cancelled agent result still names pending files and undo cards', () {
    final result = {
      'has_pending_review': true,
      'proposed_changes': [
        {'file_id': 3, 'review': {}},
        {
          'file_id': 4,
          'applied': true,
          'undo': {
            'file_id': 4,
            'file_name': 'Notes',
            'topic_id': 1,
            'topic_name': 'Health',
            'old_document_json': '%%old',
            'changes': [
              {'op': 'add', 'text': 'hello'},
            ],
          },
        },
      ],
    };

    expect(pendingFileIdsFromAgentResult(result), [3]);
    final cards = undoCardsFromAgentResult(result);
    expect(cards, hasLength(1));
    expect(cards.first.fileId, 4);
    expect(cards.first.oldDocumentJson, '%%old');
  });

  test('automation run walks each agent step for a silent discard', () {
    final result = {
      'run': {
        'status': 'completed',
        'result': {
          'steps': [
            {
              'agent': {
                'has_pending_review': true,
                'proposed_changes': [
                  {'file_id': 8, 'review': {}},
                ],
              },
            },
            {'summary': 'rotated'},
            {
              'agent': {
                'applied': true,
                'proposed_changes': [
                  {
                    'file_id': 9,
                    'applied': true,
                    'undo': {
                      'file_id': 9,
                      'file_name': 'Log',
                      'topic_id': 2,
                      'topic_name': 'Work',
                      'old_document_json': '%%before',
                    },
                  },
                ],
              },
            },
          ],
        },
      },
    };

    final agents = agentResultsFromAutomationRun(result);
    expect(agents, hasLength(2));
    expect(pendingFileIdsFromAgentResult(agents[0]), [8]);
    expect(undoCardsFromAgentResult(agents[1]).single.fileId, 9);
  });
}
