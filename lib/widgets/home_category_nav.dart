// lib/widgets/home_category_nav.dart
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Horizontal Apple-style Category Navigation Bar for Netmix Home
class HomeCategoryNavBar extends StatelessWidget {
  final String? selectedCategory;
  final ValueChanged<String?> onCategorySelected;
  final GlobalKey categoriesKey;
  final VoidCallback onCategoriesTap;
  final bool isCategoriesOpen;

  const HomeCategoryNavBar({
    super.key,
    required this.selectedCategory,
    required this.onCategorySelected,
    required this.categoriesKey,
    required this.onCategoriesTap,
    required this.isCategoriesOpen,
  });

  @override
  Widget build(BuildContext context) {
    final isCustomCategoryActive = selectedCategory != null &&
        selectedCategory != 'Shows' &&
        selectedCategory != 'Movies' &&
        selectedCategory != 'New & Hot';

    final categoriesLabel = isCustomCategoryActive
        ? selectedCategory!
        : 'Categories';

    return SizedBox(
      height: 40,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Pill 1: Shows
            _CategoryPill(
              label: 'Shows',
              isSelected: selectedCategory == 'Shows',
              onTap: () => onCategorySelected('Shows'),
            ),
            const SizedBox(width: 8),

            // Pill 2: Movies
            _CategoryPill(
              label: 'Movies',
              isSelected: selectedCategory == 'Movies',
              onTap: () => onCategorySelected('Movies'),
            ),
            const SizedBox(width: 8),

            // Pill 3: New & Hot
            _CategoryPill(
              label: 'New & Hot',
              isSelected: selectedCategory == 'New & Hot',
              onTap: () => onCategorySelected('New & Hot'),
            ),
            const SizedBox(width: 8),

            // Pill 4: Categories ▾ (with dropdown indicator)
            _CategoryPill(
              key: categoriesKey,
              label: categoriesLabel,
              hasDropdown: true,
              isSelected: isCategoriesOpen || isCustomCategoryActive,
              onTap: onCategoriesTap,
            ),

            // Optional 1-tap Clear chip if a filter is active
            if (selectedCategory != null) ...[
              const SizedBox(width: 8),
              _ClearFilterPill(
                onTap: () => onCategorySelected(null),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Interactive Pill Button with Apple fluid touch feedback
class _CategoryPill extends StatefulWidget {
  final String label;
  final bool isSelected;
  final bool hasDropdown;
  final VoidCallback onTap;

  const _CategoryPill({
    super.key,
    required this.label,
    this.isSelected = false,
    this.hasDropdown = false,
    required this.onTap,
  });

  @override
  State<_CategoryPill> createState() => _CategoryPillState();
}

class _CategoryPillState extends State<_CategoryPill> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final bgColor = widget.isSelected
        ? Colors.white
        : const Color(0x662C2E36);

    final textColor = widget.isSelected
        ? const Color(0xFF000000)
        : Colors.white;

    final borderColor = widget.isSelected
        ? Colors.white
        : Colors.white.withValues(alpha: 0.14);

    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _isPressed ? 0.94 : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOutQuad,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.symmetric(
            horizontal: widget.hasDropdown ? 14 : 16,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(19),
            border: Border.all(
              color: borderColor,
              width: 0.65,
            ),
            boxShadow: widget.isSelected
                ? [
                    BoxShadow(
                      color: Colors.white.withValues(alpha: 0.25),
                      blurRadius: 10,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                widget.label,
                style: GoogleFonts.inter(
                  color: textColor,
                  fontSize: 13.5,
                  fontWeight: widget.isSelected
                      ? FontWeight.w700
                      : FontWeight.w600,
                  letterSpacing: -0.2,
                ),
              ),
              if (widget.hasDropdown) ...[
                const SizedBox(width: 4),
                Icon(
                  Icons.arrow_drop_down,
                  size: 18,
                  color: textColor,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Small subtle ✕ Clear pill when any filter is active
class _ClearFilterPill extends StatelessWidget {
  final VoidCallback onTap;

  const _ClearFilterPill({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0x40E50914),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0x80E50914),
            width: 0.65,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.close, size: 13, color: Colors.white),
            const SizedBox(width: 4),
            Text(
              'All',
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Apple Liquid Glass Categories Popup
class CategoriesGlassPopup extends StatelessWidget {
  final Rect buttonRect;
  final Animation<double> animation;
  final List<String> categories;
  final String? selectedCategory;
  final ValueChanged<String> onSelectCategory;
  final VoidCallback onClose;

  const CategoriesGlassPopup({
    super.key,
    required this.buttonRect,
    required this.animation,
    required this.categories,
    required this.selectedCategory,
    required this.onSelectCategory,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final screenWidth = screenSize.width;
    final screenHeight = screenSize.height;

    const popupWidth = 265.0;
    // Align left edge of popup with the Categories ▾ button, clamped to screen edges
    final left = buttonRect.left.clamp(
      16.0,
      (screenWidth - popupWidth - 16.0).clamp(16.0, screenWidth),
    );

    final top = buttonRect.bottom + 6.0;
    final maxPopupHeight = (screenHeight - top - 32.0).clamp(200.0, 520.0);

    return Positioned.fill(
      child: Stack(
        children: [
          // Dismiss barrier on tap outside
          GestureDetector(
            onTap: onClose,
            behavior: HitTestBehavior.opaque,
            child: AnimatedBuilder(
              animation: animation,
              builder: (context, _) {
                return Container(
                  color: Colors.black.withValues(
                    alpha: 0.40 * animation.value,
                  ),
                );
              },
            ),
          ),

          // Floating Apple Liquid Glass Panel
          Positioned(
            left: left,
            top: top,
            width: popupWidth,
            child: AnimatedBuilder(
              animation: animation,
              builder: (context, child) {
                return Transform.scale(
                  scale: 0.92 + (0.08 * animation.value),
                  alignment: Alignment.topCenter,
                  child: Opacity(
                    opacity: animation.value.clamp(0.0, 1.0),
                    child: child,
                  ),
                );
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                  child: Container(
                    constraints: BoxConstraints(maxHeight: maxPopupHeight),
                    decoration: BoxDecoration(
                      color: const Color(0xEB161720),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.16),
                        width: 0.75,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.65),
                          blurRadius: 36,
                          spreadRadius: 2,
                          offset: const Offset(0, 14),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(
                          vertical: 10,
                          horizontal: 8,
                        ),
                        physics: const BouncingScrollPhysics(),
                        shrinkWrap: true,
                        itemCount: categories.length,
                        itemBuilder: (context, index) {
                          final category = categories[index];
                          final isSelected = selectedCategory == category ||
                              (category == 'All Categories' &&
                                  selectedCategory == null);

                          return _PopupCategoryItem(
                            title: category,
                            isSelected: isSelected,
                            onTap: () => onSelectCategory(category),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PopupCategoryItem extends StatefulWidget {
  final String title;
  final bool isSelected;
  final VoidCallback onTap;

  const _PopupCategoryItem({
    required this.title,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_PopupCategoryItem> createState() => _PopupCategoryItemState();
}

class _PopupCategoryItemState extends State<_PopupCategoryItem> {
  bool _isHoveredOrPressed = false;

  @override
  Widget build(BuildContext context) {
    Color itemBg = Colors.transparent;
    if (widget.isSelected) {
      itemBg = const Color(0x28FFFFFF);
    } else if (_isHoveredOrPressed) {
      itemBg = const Color(0x18FFFFFF);
    }

    final textColor = widget.isSelected
        ? Colors.white
        : Colors.white.withValues(alpha: 0.90);

    return InkWell(
      onTap: widget.onTap,
      onHighlightChanged: (v) => setState(() => _isHoveredOrPressed = v),
      borderRadius: BorderRadius.circular(12),
      splashColor: Colors.white.withValues(alpha: 0.08),
      highlightColor: Colors.white.withValues(alpha: 0.05),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: itemBg,
          borderRadius: BorderRadius.circular(12),
          border: widget.isSelected
              ? Border.all(
                  color: Colors.white.withValues(alpha: 0.22),
                  width: 0.65,
                )
              : null,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                widget.title,
                style: GoogleFonts.inter(
                  color: textColor,
                  fontSize: 14,
                  fontWeight: widget.isSelected
                      ? FontWeight.w700
                      : FontWeight.w500,
                  letterSpacing: -0.15,
                ),
              ),
            ),
            if (widget.isSelected)
              Icon(
                Icons.check,
                size: 16,
                color: textColor,
              ),
          ],
        ),
      ),
    );
  }
}
