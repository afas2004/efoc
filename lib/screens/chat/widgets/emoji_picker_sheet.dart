import 'package:flutter/material.dart';

import '../../../theme/colors.dart';

/// Full emoji picker behind the "+" in the quick-reaction bar.
/// Pops with the chosen emoji.
Future<String?> showEmojiPickerSheet(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => const _EmojiPickerSheet(),
  );
}

class _Category {
  final IconData icon;
  final String name;
  final String emojis;

  const _Category(this.icon, this.name, this.emojis);

  List<String> get list => emojis.split(' ');
}

const _categories = [
  _Category(
    Icons.emoji_emotions_outlined,
    'Smileys & people',
    '😀 😃 😄 😁 😆 😅 😂 🤣 🥲 ☺️ 😊 😇 🙂 🙃 😉 😌 😍 🥰 😘 😗 😙 😚 '
        '😋 😛 😝 😜 🤪 🤨 🧐 🤓 😎 🥸 🤩 🥳 😏 😒 😞 😔 😟 😕 🙁 ☹️ 😣 '
        '😖 😫 😩 🥺 😢 😭 😤 😠 😡 🤬 🤯 😳 🥵 🥶 😱 😨 😰 😥 😓 🤗 🤔 '
        '🫣 🤭 🫢 🫡 🤫 🫠 🤥 😶 🫥 😐 🫤 😑 😬 🙄 😯 😦 😧 😮 😲 🥱 😴 '
        '🤤 😪 😵 😵‍💫 🤐 🥴 🤢 🤮 🤧 😷 🤒 🤕 🤑 🤠 😈 👿 👹 👺 🤡 💩 👻 '
        '💀 ☠️ 👽 👾 🤖 🎃 😺 😸 😹 😻 😼 😽 🙀 😿 😾',
  ),
  _Category(
    Icons.back_hand_outlined,
    'Gestures',
    '👋 🤚 🖐️ ✋ 🖖 👌 🤌 🤏 ✌️ 🤞 🫰 🤟 🤘 🤙 👈 👉 👆 🖕 👇 ☝️ 🫵 👍 '
        '👎 ✊ 👊 🤛 🤜 👏 🙌 🫶 👐 🤲 🤝 🙏 ✍️ 💅 🤳 💪 🦾 🦵 🦶 👂 👃 🧠 '
        '👀 👁️ 👅 👄 🫦 💋',
  ),
  _Category(
    Icons.favorite_border_rounded,
    'Hearts & symbols',
    '❤️ 🧡 💛 💚 💙 💜 🖤 🤍 🤎 🩷 🩵 🩶 💔 ❤️‍🔥 ❤️‍🩹 ❣️ 💕 💞 💓 💗 💖 💘 '
        '💝 💟 💯 💢 💥 💫 💦 💨 🕳️ 💬 💭 💤 ✨ ⭐ 🌟 ⚡ 🔥 ✅ ❌ ❓ ❗ '
        '‼️ ⁉️ 💲 ♻️ 🆗 🆒 🆕 🔝 🎵 🎶',
  ),
  _Category(
    Icons.pets_outlined,
    'Animals & nature',
    '🐶 🐱 🐭 🐹 🐰 🦊 🐻 🐼 🐨 🐯 🦁 🐮 🐷 🐸 🐵 🙈 🙉 🙊 🐔 🐧 🐦 🐤 '
        '🦆 🦅 🦉 🐺 🐗 🐴 🦄 🐝 🐛 🦋 🐌 🐞 🐢 🐍 🦖 🐙 🦑 🦀 🐠 🐟 🐬 '
        '🐳 🦈 🐊 🐘 🦒 🐪 🐈 🐓 🦚 🦜 🌵 🎄 🌲 🌴 🌱 🌿 🍀 🍁 🍂 🌷 🌹 '
        '🥀 🌺 🌸 🌼 🌻 🌞 🌝 🌚 🌙 🌎 🪐 ☀️ 🌤️ ⛅ 🌧️ ⛈️ 🌈 ❄️ ☃️ 🌊',
  ),
  _Category(
    Icons.restaurant_outlined,
    'Food & drink',
    '🍏 🍎 🍐 🍊 🍋 🍌 🍉 🍇 🍓 🫐 🍒 🍑 🥭 🍍 🥥 🥝 🍅 🥑 🍆 🥔 🥕 🌽 '
        '🌶️ 🥒 🥦 🧄 🧅 🍄 🥜 🍞 🥐 🥖 🧀 🥚 🍳 🥞 🧇 🥓 🍗 🍖 🌭 🍔 🍟 '
        '🍕 🥪 🌮 🌯 🥗 🍝 🍜 🍲 🍛 🍣 🍱 🥟 🍤 🍙 🍚 🍘 🍥 🍢 🍡 🍧 🍨 '
        '🍦 🥧 🧁 🍰 🎂 🍮 🍭 🍬 🍫 🍿 🍩 🍪 ☕ 🍵 🧋 🥤 🧃 🍺 🍻 🥂 🍷',
  ),
  _Category(
    Icons.sports_soccer_outlined,
    'Activities & travel',
    '⚽ 🏀 🏈 ⚾ 🎾 🏐 🏉 🎱 🏓 🏸 🥊 🥋 ⛳ 🏹 🎣 🛹 ⛸️ 🎿 🏂 🏋️ 🤸 '
        '🏊 🚴 🏆 🥇 🥈 🥉 🏅 🎖️ 🎗️ 🎫 🎟️ 🎪 🎭 🎨 🎬 🎤 🎧 🎼 🎹 🥁 🎷 '
        '🎺 🎸 🎻 🎲 ♟️ 🎯 🎳 🎮 🎰 🧩 🚗 🚕 🚌 🏎️ 🚓 🚑 🚒 🛵 🏍️ 🚲 ✈️ '
        '🚀 🛸 🚁 ⛵ 🚢 🗽 🗼 🏰 🎡 🎢 🏖️ 🏝️ 🏔️ ⛺ 🏠 🏙️ 🌃 🌅 🎆 🎇',
  ),
  _Category(
    Icons.lightbulb_outline_rounded,
    'Objects',
    '⌚ 📱 💻 ⌨️ 🖥️ 🖨️ 🕹️ 📷 📸 📹 🎥 📞 ☎️ 📺 📻 ⏰ ⌛ 🔋 🔌 💡 🔦 🕯️ '
        '💸 💵 💰 💳 💎 ⚖️ 🔧 🔨 ⚙️ 🧲 💣 🔪 🛡️ 💊 💉 🩹 🧬 🔭 🔬 🧹 🧺 '
        '🧻 🚽 🛁 🔑 🗝️ 🚪 🛋️ 🛏️ 🧸 🎁 🎈 🎀 🎊 🎉 ✉️ 📦 📝 📌 📎 ✂️ 📚 '
        '📖 🔒 🔓',
  ),
];

class _EmojiPickerSheet extends StatefulWidget {
  const _EmojiPickerSheet();

  @override
  State<_EmojiPickerSheet> createState() => _EmojiPickerSheetState();
}

class _EmojiPickerSheetState extends State<_EmojiPickerSheet> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height * 0.55;
    final category = _categories[_tab];

    return Container(
      height: height,
      decoration: const BoxDecoration(
        color: EfocColors.sheetBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFF333333),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  for (int i = 0; i < _categories.length; i++)
                    IconButton(
                      onPressed: () => setState(() => _tab = i),
                      icon: Icon(
                        _categories[i].icon,
                        size: 20,
                        color: i == _tab
                            ? EfocColors.accentBright
                            : Colors.white38,
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  category.name,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            Expanded(
              child: GridView.count(
                key: ValueKey(_tab),
                crossAxisCount: 8,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: [
                  for (final e in category.list)
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => Navigator.of(context).pop(e),
                      child: Center(
                        child: Text(e, style: const TextStyle(fontSize: 26)),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
