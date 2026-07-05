import 'package:flutter/material.dart';
import 'package:momeo/pages/dev/catalog/catalog_detail_page.dart';
import 'package:momeo/pages/dev/catalog/sections/foundation/foundation_app_colors_section.dart';
import 'package:momeo/pages/dev/catalog/sections/foundation/foundation_app_text_styles_section.dart';
import 'package:momeo/pages/dev/catalog/sections/foundation/foundation_app_spacing_section.dart';
import 'package:momeo/pages/dev/catalog/sections/foundation/foundation_app_radius_section.dart';
import 'package:momeo/pages/dev/catalog/sections/foundation/foundation_app_theme_section.dart';
import 'package:momeo/pages/dev/catalog/sections/widgets/widgets_animated_text_sequence_section.dart';
import 'package:momeo/pages/dev/catalog/sections/widgets/widgets_content_slide_switcher_section.dart';
import 'package:momeo/pages/dev/catalog/sections/widgets/widgets_intro_setting_layout_section.dart';
import 'package:momeo/pages/dev/catalog/sections/widgets/widgets_voice_icon_section.dart';
import 'package:momeo/pages/dev/catalog/sections/widgets/widgets_voice_card_section.dart';
import 'package:momeo/pages/dev/catalog/sections/packages/packages_record_section.dart';
import 'package:momeo/pages/dev/catalog/sections/packages/packages_sherpa_onnx_section.dart';
import 'package:momeo/pages/dev/catalog/sections/stt/stt_vad_section.dart';
import 'package:momeo/pages/dev/catalog/sections/stt/stt_models_section.dart';
import 'package:momeo/pages/dev/catalog/sections/stt/stt_transcription_section.dart';
import 'package:momeo/pages/dev/catalog/sections/stt/stt_engine_section.dart';

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
    _Item(title: 'ContentSlideSwitcher', body: WidgetsContentSlideSwitcherSection()),
  ]),
  _Section(title: 'Packages', items: [
    _Item(title: 'record', body: PackagesRecordSection()),
    _Item(title: 'sherpa_onnx', body: PackagesSherpaOnnxSection()),
  ]),
  _Section(title: 'STT', items: [
    _Item(title: 'VAD 区切り', body: SttVadSection()),
    _Item(title: 'モデル配置', body: SttModelsSection()),
    _Item(title: '文字化', body: SttTranscriptionSection()),
    _Item(title: 'エンジン常駐', body: SttEngineSection()),
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
