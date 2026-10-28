# Reeded Light

A shop window is a lens that sells. Behind the glass sits the object, but what reaches the eye is the
glass's account of it: bent, sliced and lit along its edges. Reeded Light is a generative movement about
that account. It never draws the thing on show. It draws a field of light, sets fluted glass in front of
it, and lets refraction decide the picture.

The process starts as an invisible scene: a few soft sources of colored light, placed by the seed, their
shapes slowly warped by layered noise so that no two glows share an edge. Among them rests one brighter
disc, set off the center at the golden section, its surface cut with grooves too fine to see directly.
This scene is computed once, in full, and kept out of sight. Everything the viewer sees is a reading of
it through glass.

The glass is a row of cylindrical flutes, each one a small lens. A flute gathers a strip of the scene
wider than itself, turns it over and squeezes it into its own width, so a soft glow becomes a set of
sharp bands and the hidden disc breaks into a stack of bright staves. Each color channel is bent by a
slightly different amount, so dispersion fringes every flute's edge with the spectrum, the way real glass
does when light crosses it at an angle. The ridges darken where the curve turns away and carry a thin
specular line where it faces the light. The pane is inset from the frame like glass in a cabinet, its rim
catching one bright line, and the unrefracted scene glows dimly around it.

Every quantity is a ratio, not a constant: the flute width to the pane, the lens power to the flute,
the dispersion to the lens power, the disc to the golden section. The work is the balance of those
ratios. At full size the flutes read as craft, with fringes, highlights and the ghost of grooves. At the
size of a fingertip they must still read as one bright, split form behind glass. Getting both from one
algorithm is a meticulously tuned piece of work: refined through many iterations, with each parameter
adjusted until the small render and the large one agree.

Seeds change where the light sits and how the noise warps it, never the rules of the glass. Each seed is
a different window display behind the same pane. The algorithm should feel like the product of deep
computational craft and master-level care for detail: sampling filtered so the bands never alias,
fringes subtle enough to look optical rather than digital, and a palette held to warm reds and violets
over near-black, so that every run looks considered and none looks random.
