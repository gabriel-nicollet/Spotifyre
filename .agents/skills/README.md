# Agent skills

Skills for agents working on the mod. Each directory is one skill, a `SKILL.md` and the files it
reads. `.claude/skills/` links each one back here, so Claude Code and the agents that read
`.agents/skills/` load the same copy.

    liquid-glass/          Liquid Glass APIs, migration and pitfalls; SwiftUI first, with UIKit in
                           references/uikit.md, which is what the tweak builds on
    apple-hig/             design review against Apple's Human Interface Guidelines, 122 pages under
                           references/hig/, liquid-glass.md, materials.md, tab-bars.md and motion.md among them
    apple-design/          Designing Fluid Interfaces: springs by damping and response, velocity handoff,
                           momentum projection, rubber-banding, interruptible transitions, materials
    review-animations/     a strict review of motion code, `/review-animations`; STANDARDS.md holds the values
    animation-vocabulary/  the name of a motion effect you can describe but not name
    phone-check/           install a build on the phone, drive it, take screenshots, read the tree and log
    clean-room-describer/  learn what upstream changed or what its users report, as behavior only
    spotify-version-check/ check the tweak against a new Spotify version, and read a Spotify method from the binary

The motion skills write their examples in CSS and JavaScript. The rules carry over to UIKit as they
are: a spring is `-[UISpringTimingParameters initWithDampingRatio:initialVelocity:]` on a
`UIViewPropertyAnimator`, an interruption starts from `layer.presentationLayer`, and reduced motion
is `UIAccessibilityIsReduceMotionEnabled()`.

## Where they come from

`phone-check` and `clean-room-describer` are Vitrine's own. The rest are
copied unchanged unless noted. To update one, copy the upstream directory over it and redo the note.

| Skill | Upstream | Commit | License |
| --- | --- | --- | --- |
| `liquid-glass` | [haider-nawaz/liquid-glass-skill](https://github.com/haider-nawaz/liquid-glass-skill) `plugins/liquid-glass/skills/liquid-glass` | `2c1b278` | MIT, as its README and plugin.json state |
| `apple-hig` | [dickwu/apple-design-skill](https://github.com/dickwu/apple-design-skill) `SKILL.md`, `references/`, `scripts/` | `da2da6d` | none given; the guideline text in `references/hig/` belongs to Apple Inc. |
| `apple-design` | [emilkowalski/skills](https://github.com/emilkowalski/skills) `skills/apple-design` | `85e8e23` | MIT, `LICENSE` beside it |
| `review-animations` | [emilkowalski/skills](https://github.com/emilkowalski/skills) `skills/review-animations` | `85e8e23` | MIT, `LICENSE` beside it |
| `animation-vocabulary` | [emilkowalski/skills](https://github.com/emilkowalski/skills) `skills/animation-vocabulary` | `85e8e23` | MIT, `LICENSE` beside it |

`liquid-glass` adds `references/uikit.md`, written here from the iOS SDK headers and `Core/SGGlass.m`.
It also links that file from `SKILL.md` and `references/api-reference.md`, and changes the bridge's bare
`UIGlassEffect()` to `UIGlassEffect(style: .regular)`, because a bare init draws a plain blur.

`apple-hig` is named `apple-design` upstream; its `name:` was changed so it does not collide with
Emil Kowalski's `apple-design`. `node .agents/skills/apple-hig/scripts/pull-hig.mjs` pulls the
guideline pages again from developer.apple.com.

These files are not part of the mod and not covered by the GPL-3.0 license of this repository.
