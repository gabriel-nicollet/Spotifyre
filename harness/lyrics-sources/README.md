# Lyrics sources check

`./build.sh` checks, on the Mac as a Mac Catalyst binary, with no simulator and no network:

- the word splitting in `Shared/Lyrics/KaraokeTiming.m`: long Thai, Lao, Khmer and Burmese lines with no
  spaces come apart at the dictionary's words, the pieces make up the line exactly, and Latin, Chinese and
  Japanese lines split as before. The pieces are printed, so a script the system does not split shows;
- KuGou's KRC (`KuGou.m`, read by `SGLyricsPieceLines` in `NetEase.m`): packed here the way KuGou packs
  it, then unpacked and read, with the word times, the joining and the line ends checked;
- the QQ Music and KuGou asks against made-up search replies: titles, singers and lengths that do not
  fit are passed over, the closest KuGou lengths are tried first and at most three, and QQ's LRC is read.

`./build.sh krc.json qq.json` also reads real replies saved from `lyrics.kugou.com/download` and QQ's
`GetPlayLyricInfo`, and prints how many lines each has. None are kept here, since they are real lyrics.

It does not cover the requests themselves, the order on the Lyrics page, or the lines on the lyrics view.
