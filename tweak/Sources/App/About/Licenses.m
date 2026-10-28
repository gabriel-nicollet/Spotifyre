// Mod > Licenses: the mod's own license, then each third-party one the build ships code under, in full,
// since the MIT license asks for its text to travel with every copy.
#import "Core/SGCore.h"
#import "Settings/SGPageStyle.h"
#import "About.h"

static NSString *const kMIT =
    @"Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated "
    @"documentation files (the \"Software\"), to deal in the Software without restriction, including without "
    @"limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the "
    @"Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:\n\n"
    @"The above copyright notice and this permission notice shall be included in all copies or substantial portions "
    @"of the Software.\n\n"
    @"THE SOFTWARE IS PROVIDED \"AS IS\", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED "
    @"TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE "
    @"AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF "
    @"CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER "
    @"DEALINGS IN THE SOFTWARE.";

static NSString *const kZlib =
    @"This software is provided 'as-is', without any express or implied warranty. In no event will the authors be "
    @"held liable for any damages arising from the use of this software.\n\n"
    @"Permission is granted to anyone to use this software for any purpose, including commercial applications, and "
    @"to alter it and redistribute it freely, subject to the following restrictions:\n\n"
    @"1. The origin of this software must not be misrepresented; you must not claim that you wrote the original "
    @"software. If you use this software in a product, an acknowledgment in the product documentation would be "
    @"appreciated but is not required.\n\n"
    @"2. Altered source versions must be plainly marked as such, and must not be misrepresented as being the "
    @"original software.\n\n"
    @"3. This notice may not be removed or altered from any source distribution.";

UIViewController *SGLicensesPage(void) {
    SGModRow *mod = SGLinkRow(@"Vitrine", @"GNU General Public License v3.0", @"https://www.gnu.org/licenses/gpl-3.0.html");
    SGModRow *bs2b = SGLinkRow(@"libbs2b", @"Crossfeed · MIT License", @"https://github.com/alexmarsev/libbs2b");
    SGModRow *wdl = SGLinkRow(@"WDL", @"Liveprog's EEL2 · zlib License", @"https://github.com/justinfrankel/WDL");
    // EeveeSpotify's repo was taken down, so the row opens the license both projects are under.
    SGModRow *eevee = SGLinkRow(@"EeveeSpotify", @"Ads, upsells, Spoof Premium · GNU GPL v3.0", @"https://www.gnu.org/licenses/gpl-3.0.html");
    // Not shipped: the Headphones page downloads its results when asked, but they are AutoEq's work all the same.
    SGModRow *autoEq = SGLinkRow(@"AutoEq", @"Headphone corrections · MIT License", @"https://github.com/jaakkopasanen/AutoEq");
    // Sing's voice model is downloaded rather than built in, and its NOTICE travels with it here all the same.
    SGModRow *voice = SGLinkRow(@"Karaoke's voice model", @"Mel-Band RoFormer · MIT License", @"https://huggingface.co/My-Name-Is-Jeff/vitrine-sing");
    SGModRow *lightVoice = SGLinkRow(@"Karaoke's light voice model", @"Mini-BS-RoFormer-18M · MIT License",
                                     @"https://huggingface.co/HiDolen/Mini-BS-RoFormer-18M");
    return [[SGModPage alloc] initWithTitle:@"Licenses" intro:@"The mod's own license, and the code from others it includes." sections:@[
        SGSection(nil, @[mod]),
        SGNotedSection(nil, @[eevee], @"By whoeevee (whoeevee/EeveeSpotify), under the GNU General Public License v3.0, as Vitrine is.\n\n"
                                      @"Ported from it, on the Premium, ads & privacy page: Hide ads (the ad services kept from starting, "
                                      @"ad components taken out of Home and Search, ad sections out of the feeds, ad requests answered empty), "
                                      @"Hide upsells (the Premium pop-ups, and the ad and upsell flags it turns off) and Spoof Premium "
                                      @"(the account attributes and flag rules it rewrites, and crossfade under it)."),
        SGNotedSection(nil, @[bs2b], [@"Copyright (c) 2005 Boris Mikhaylov\n\n" stringByAppendingString:kMIT]),
        SGNotedSection(nil, @[wdl], [@"Copyright (C) 2004-2013 Cockos Incorporated\nCopyright (C) 1999-2003 Nullsoft, Inc.\n\n"
                                     stringByAppendingString:kZlib]),
        SGNotedSection(nil, @[autoEq], [@"Copyright (c) 2018-2022 Jaakko Pasanen\n\n" stringByAppendingString:kMIT]),
        SGNotedSection(nil, @[voice], [@"Mel-Band RoFormer vocal separation, by Ju-Chiang Wang, Wei-Tsung Lu and Minz Won.\n"
                                       @"Checkpoint: KimberleyJensen, https://huggingface.co/KimberleyJSN/melbandroformer (MIT).\n"
                                       @"Core ML conversion: john-rocky / mlboydaisuke, https://huggingface.co/mlboydaisuke/MelBandRoformer-Vocal-CoreAI (MIT).\n"
                                       @"Core ML export: Darkkos, https://huggingface.co/Darkkos/spoti-sing (MIT), mirrored unchanged.\n"
                                       @"Neural Engine export, the model Karaoke downloads: Vitrine, from the same checkpoint, palettized to 6 bits.\n"
                                       @"Reference architecture: lucidrains/BS-RoFormer. Training code: ZFTurbo.\n\n"
                                       @"Copyright (c) 2023 Phil Wang\n\n" stringByAppendingString:kMIT]),
        SGNotedSection(nil, @[lightVoice], [@"Mini-BS-RoFormer-18M by HiDolen, revision d3ff400db0c72c236775ecc82e038f3117e52bf8, whose model card "
                                            @"declares the MIT License. Its code is adapted from lucidrains/BS-RoFormer (MIT, Copyright (c) 2023 "
                                            @"Phil Wang, above).\n"
                                            @"Core ML export of its vocals, the light model Karaoke downloads: Vitrine, in float16, from "
                                            @"https://huggingface.co/My-Name-Is-Jeff/vitrine-sing.\n\n"
                                            @"Copyright (c) HiDolen (the model card gives no year)\n\n" stringByAppendingString:kMIT]),
    ] footer:nil];
}
