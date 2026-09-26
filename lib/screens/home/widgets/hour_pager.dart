import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../state/app_state.dart';
import 'grid_cell.dart';

typedef CellTapCallback = void Function(int memberIdx, int hourIdx);

class HourPager extends StatefulWidget {
  final PageController controller;
  final CellTapCallback onCellTap;

  const HourPager({
    super.key,
    required this.controller,
    required this.onCellTap,
  });

  @override
  State<HourPager> createState() => _HourPagerState();
}

class _HourPagerState extends State<HourPager> {
  bool _initialJumpDone = false;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final visible = state.visibleHourIndices;

    if (visible.isEmpty) {
      return const _EmptyHours();
    }

    if (!_initialJumpDone) {
      final target = state.currentPageIndex;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.controller.hasClients && !_initialJumpDone) {
          widget.controller.jumpToPage(target);
          _initialJumpDone = true;
        }
      });
    }

    return PageView.builder(
      controller: widget.controller,
      itemCount: visible.length,
      onPageChanged: (pageIdx) => state.setPage(pageIdx),
      itemBuilder: (context, pageIdx) {
        final hourIdx = visible[pageIdx];
        return _HourPage(hourIdx: hourIdx, onCellTap: widget.onCellTap);
      },
    );
  }
}

class _HourPage extends StatelessWidget {
  final int hourIdx;
  final CellTapCallback onCellTap;

  const _HourPage({required this.hourIdx, required this.onCellTap});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final members = state.currentGroup.members;
    final cols = members.length < 3 ? 1 : 2;

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (cols == 1) ...[
            for (int i = 0; i < members.length; i++) ...[
              if (i > 0) const SizedBox(height: 2),
              AspectRatio(
                aspectRatio: 16 / 10,
                child: EfocGridCell(
                  memberIdx: i,
                  hourIdx: hourIdx,
                  onTap: () => onCellTap(i, hourIdx),
                ),
              ),
            ],
          ] else ...[
            for (int row = 0; row < (members.length / 2).ceil(); row++) ...[
              if (row > 0) const SizedBox(height: 2),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: AspectRatio(
                      aspectRatio: 1 / 1.05,
                      child: EfocGridCell(
                        memberIdx: row * 2,
                        hourIdx: hourIdx,
                        onTap: () => onCellTap(row * 2, hourIdx),
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  if (row * 2 + 1 < members.length)
                    Expanded(
                      child: AspectRatio(
                        aspectRatio: 1 / 1.05,
                        child: EfocGridCell(
                          memberIdx: row * 2 + 1,
                          hourIdx: hourIdx,
                          onTap: () => onCellTap(row * 2 + 1, hourIdx),
                        ),
                      ),
                    )
                  else
                    const Spacer(),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _EmptyHours extends StatelessWidget {
  const _EmptyHours();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.schedule_outlined,
              size: 40,
              color: Colors.white.withValues(alpha: 0.15),
            ),
            const SizedBox(height: 14),
            Text(
              'Nothing to show yet',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Your next capture window opens soon.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.3),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}