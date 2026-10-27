# Liquid Glass in UIKit

UIKit's glass APIs, checked against the iOS 27 SDK headers, with the rules the tweak proved on the
phone. The tweak is Objective-C, so the examples are too. Everything here is iOS 26 and later. Gate
it with `@available(iOS 26.0, *)`, or with `NSClassFromString` and `respondsToSelector:` as
`Core/SGGlass.m` does.

## UIGlassEffect

```objc
UIGlassEffect *effect = [UIGlassEffect effectWithStyle:UIGlassEffectStyleRegular];
effect.interactive = YES;                     // scales and shimmers under a touch
effect.tintColor = UIColor.systemPinkColor;   // nullable
UIVisualEffectView *glass = [[UIVisualEffectView alloc] initWithEffect:effect];
[glass.contentView addSubview:label];
```

- `+effectWithStyle:` is the only initializer. A bare `-init` (Swift `UIGlassEffect()`) leaves the
  material unresolved, so the pane draws as a plain blur. Spotify's own glass uses `+effectWithStyle:`.
- `UIGlassEffectStyleRegular` suits controls and bars. `UIGlassEffectStyleClear` suits glass over
  bright media with bold content on it.
- Put content in `contentView`, not directly in the effect view.
- `SGGlassEffect()` returns the regular glass, or a dark chrome blur before iOS 26.

## Shape

Glass takes its shape from `UIView.cornerConfiguration`, not from `layer.cornerRadius`.

```objc
glass.cornerConfiguration = [UICornerConfiguration capsuleConfiguration];
glass.cornerConfiguration = [UICornerConfiguration configurationWithUniformRadius:[UICornerRadius fixedRadius:20]];
glass.cornerConfiguration = [UICornerConfiguration configurationWithUniformRadius:[UICornerRadius containerConcentricRadius]];
glass.clipsToBounds = NO;
```

- `capsuleConfiguration` scales with the view's size. `capsuleConfigurationWithMaximumRadius:` caps it.
- `containerConcentricRadius` computes the radius from the view and its container.
  `containerConcentricRadiusWithMinimum:` sets a floor.
- `-effectiveRadiusForCorner:` returns the radius a configuration resolved to.
- Before iOS 26, use `layer.cornerRadius` with `kCACornerCurveContinuous` and `clipsToBounds = YES`.
  `SGShapeGlass` (`Core/SGGlass.h`) does both.

## Grouping: UIGlassContainerEffect

Glass can't sample other glass, so glass views that sit close together go in one container. Its
`spacing` is the distance at which the elements begin to merge.

```objc
UIGlassContainerEffect *group = [UIGlassContainerEffect new];
group.spacing = 12;
UIVisualEffectView *container = [[UIVisualEffectView alloc] initWithEffect:group];
[container.contentView addSubview:glassA];   // each a UIVisualEffectView with a UIGlassEffect
[container.contentView addSubview:glassB];
```

The tweak doesn't use it yet, so check merging and morphing on the phone before you rely on them.

## Scroll edge effects

Every `UIScrollView` has `topEdgeEffect`, `bottomEdgeEffect`, `leftEdgeEffect` and `rightEdgeEffect`.
Each is a read-only `UIScrollEdgeEffect` with a `style` and a `hidden` flag. The styles are class
properties of `UIScrollEdgeEffectStyle`, not an enum:

| Style | Look |
| --- | --- |
| `automaticStyle` | the system picks |
| `softStyle` | a thin fading blur |
| `hardStyle` | a hard cutoff with a dividing line |

```objc
scrollView.topEdgeEffect.style = UIScrollEdgeEffectStyle.softStyle;
scrollView.bottomEdgeEffect.hidden = YES;
```

iOS 27 resolves an automatic top edge to the hard style, and UIKit can resolve it again after the
page appears. `Redesigned/Kit/SGREdgeEffect.x` and `Native/Appearance/EdgeEffect.x` set the soft
style on `didMoveToWindow` and on every `layoutSubviews`.

## UIScrollEdgeElementContainerInteraction

Add it to a container of views that overlay a scroll view's edge, such as a floating button bar.
Labels, images, glass views and controls inside the container then shape the edge effect.

```objc
UIScrollEdgeElementContainerInteraction *interaction = [UIScrollEdgeElementContainerInteraction new];
interaction.scrollView = scrollView;   // weak
interaction.edge = UIRectEdgeBottom;
[buttonContainer addInteraction:interaction];
```

## Bar button items

- `hidesSharedBackground` (default `NO`): `YES` draws the item alone, without the shared glass background.
- `sharesBackground` (default `YES`): `NO` stops the item from being grouped with other items.
- Both are ignored for an item in a `UIBarButtonItemGroup` with more than one item.

## Buttons

`UIButtonConfiguration` has four glass constructors: `glassButtonConfiguration`,
`prominentGlassButtonConfiguration`, `clearGlassButtonConfiguration` and
`prominentClearGlassButtonConfiguration`.

## Background extension

`UIBackgroundExtensionView` is UIKit's `backgroundExtensionEffect`. Set its `contentView`. With
`automaticallyPlacesContentView` (default `YES`), it places the content in the safe area and extends
it to fill the view around it.

## Tab bar

- `UITabBarController.tabBarMinimizeBehavior`: `UITabBarMinimizeBehaviorAutomatic` (default),
  `…Never`, `…OnScrollDown` or `…OnScrollUp`.
- `bottomAccessory` takes a `UITabAccessory` made with `-initWithContentView:`. Use
  `-setBottomAccessory:animated:` to animate the change.

## Appearance in the tweak

Glass takes the appearance it inherits. Outside Spotify's navigation stacks (the tab bar, the now
playing bar, the player) that is the system's, so set `overrideUserInterfaceStyle =
UIUserInterfaceStyleDark` on every pane of the mod's. Present a controller of the mod's through
`SGPresentDark`, because a sheet's glass belongs to its presentation.
