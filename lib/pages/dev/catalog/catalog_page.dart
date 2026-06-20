import 'package:flutter/material.dart';
import 'package:momeo/pages/dev/catalog/catalog_detail_page.dart';
import 'package:momeo/pages/dev/catalog/sections/foundation/foundation_app_colors_section.dart';
import 'package:momeo/pages/dev/catalog/sections/foundation/foundation_app_text_styles_section.dart';
import 'package:momeo/pages/dev/catalog/sections/foundation/foundation_app_spacing_section.dart';
import 'package:momeo/pages/dev/catalog/sections/foundation/foundation_app_radius_section.dart';
import 'package:momeo/pages/dev/catalog/sections/foundation/foundation_app_theme_section.dart';
import 'package:momeo/pages/dev/catalog/sections/widgets/widgets_animated_text_sequence_section.dart';
import 'package:momeo/pages/dev/catalog/sections/widgets/widgets_intro_setting_layout_section.dart';
import 'package:momeo/pages/dev/catalog/sections/widgets/widgets_voice_icon_section.dart';
import 'package:momeo/pages/dev/catalog/sections/widgets/widgets_voice_card_section.dart';
import 'package:momeo/pages/dev/catalog/sections/stt/stt_case_c_spike_section.dart';

// ---------------------------------
// データ定義
// ---------------------------------

// カタログの1アイテム（タイトル + 詳細ページに表示する body）
class _Item {
  final String title;
  final Widget body;
  const _Item({required this.title, required this.body});
}

// カタログのセクション（タイトル + アイテム一覧）
class _Section {
  final String title;
  final List<_Item> items;
  const _Section({required this.title, required this.items});
}

// セクションとアイテムの対応をここで一元管理する
// アイテムを追加するときはここだけ変えればよい
const _sections = [
  _Section(title: 'Foundation', items: [
    _Item(title: 'Colors',      body: FoundationAppColorsSection()),
    _Item(title: 'Text Styles', body: FoundationAppTextStylesSection()),
    _Item(title: 'Spacing',     body: FoundationAppSpacingSection()),
    _Item(title: 'Radius',      body: FoundationAppRadiusSection()),
    _Item(title: 'Theme',       body: FoundationAppThemeSection()),
  ]),
  _Section(title: 'Widgets', items: [
    _Item(title: 'IntroSettingLayout', body: WidgetsIntroSettingLayoutSection()),
    _Item(title: 'VoiceIcon', body: WidgetsVoiceIconSection()),
    _Item(title: 'VoiceCard', body: WidgetsVoiceCardSection()),
    _Item(title: 'AnimatedTextSequence', body: WidgetsAnimatedTextSequenceSection()),
  ]),
  // 案C 検証用の使い捨てセクション（research/stt-sherpa-builtin-vad）
  _Section(title: 'STT (検証)', items: [
    _Item(title: 'CaseC: sherpa VAD + record', body: SttCaseCSpikeSection()),
  ]),
];

// ---------------------------------
// ページ
// ---------------------------------

// カタログのトップページ
// セクションごとにアイテムをリスト表示し、タップで詳細ページへ遷移する
class CatalogPage extends StatelessWidget {
  const CatalogPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Catalog'),
      ),
      body: CustomScrollView(
        slivers: [
          for (final section in _sections) ...[
            // ---------------------------------
            // セクションヘッダー
            // ---------------------------------
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                child: Text(
                  section.title,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        letterSpacing: 1.2,
                      ),
                ),
              ),
            ),
            // ---------------------------------
            // アイテム一覧（未登録セクションは何も表示しない）
            // ---------------------------------
            if (section.items.isEmpty)
              const SliverToBoxAdapter(child: SizedBox.shrink())
            else
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final item = section.items[index];
                    // タップで CatalogDetailPage へ遷移（title と body を渡す）
                    return ListTile(
                      title: Text(item.title),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => CatalogDetailPage(
                              title: item.title,
                              body: item.body,
                            ),
                          ),
                        );
                      },
                    );
                  },
                  childCount: section.items.length,
                ),
              ),
          ],
        ],
      ),
    );
  }
}
