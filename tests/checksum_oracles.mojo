# Generated seed38 using Python hashlib/binascii and google-crc32c1.7.1.
from mojo_s3.crypto import bytes_of, hex_encode
from mojo_s3.checksums import checksum_digest
from std.testing import assert_equal


def checksum_oracles() raises:
    assert_equal(
        hex_encode(checksum_digest(bytes_of(""), "sha256")),
        "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
    )
    assert_equal(
        hex_encode(checksum_digest(bytes_of(""), "sha1")),
        "da39a3ee5e6b4b0d3255bfef95601890afd80709",
    )
    assert_equal(hex_encode(checksum_digest(bytes_of(""), "crc32")), "00000000")
    assert_equal(
        hex_encode(checksum_digest(bytes_of(""), "crc32c")), "00000000"
    )
    assert_equal(
        hex_encode(checksum_digest(bytes_of("%"), "sha256")),
        "bbf3f11cb5b43e700273a78d12de55e4a7eab741ed2abf13787a4d2dc832b8ec",
    )
    assert_equal(
        hex_encode(checksum_digest(bytes_of("%"), "sha1")),
        "4345cb1fa27885a8fbfe7c0c830a592cc76a552b",
    )
    assert_equal(
        hex_encode(checksum_digest(bytes_of("%"), "crc32")), "99063bca"
    )
    assert_equal(
        hex_encode(checksum_digest(bytes_of("%"), "crc32c")), "4731c993"
    )
    assert_equal(
        hex_encode(checksum_digest(bytes_of("%Ac+=+b"), "sha256")),
        "233d4747b8bdb67cc96a356aee0b2d8a85faddf4a51d1dc932c2409db2548417",
    )
    assert_equal(
        hex_encode(checksum_digest(bytes_of("%Ac+=+b"), "sha1")),
        "cad8080f75d42b8bac90a0517e6f7547d99d7340",
    )
    assert_equal(
        hex_encode(checksum_digest(bytes_of("%Ac+=+b"), "crc32")), "9433bef0"
    )
    assert_equal(
        hex_encode(checksum_digest(bytes_of("%Ac+=+b"), "crc32c")), "499644eb"
    )
    assert_equal(
        hex_encode(
            checksum_digest(
                bytes_of("C+/9/ 雪?1cé雪B%é1a?+éaB雪A9AB=cA?"), "sha256"
            )
        ),
        "779eee89decbf06328cf501d693ad73490d45b9836db382f06641ce3048e703d",
    )
    assert_equal(
        hex_encode(
            checksum_digest(bytes_of("C+/9/ 雪?1cé雪B%é1a?+éaB雪A9AB=cA?"), "sha1")
        ),
        "8c5b541f09fb43991a28224ae8a16d984bf9a5fc",
    )
    assert_equal(
        hex_encode(
            checksum_digest(
                bytes_of("C+/9/ 雪?1cé雪B%é1a?+éaB雪A9AB=cA?"), "crc32"
            )
        ),
        "fd332be3",
    )
    assert_equal(
        hex_encode(
            checksum_digest(
                bytes_of("C+/9/ 雪?1cé雪B%é1a?+éaB雪A9AB=cA?"), "crc32c"
            )
        ),
        "7d822934",
    )
    assert_equal(
        hex_encode(
            checksum_digest(
                bytes_of(
                    " C+=%雪 9C%9C+c1é1 aB%1+caé+b1?B=cCb=aB?Bé90b/9ac=0 9B%Caé 1?bAéc"
                ),
                "sha256",
            )
        ),
        "298960e922cd642f6e22056d3246fd7533d28a947e78ab40ea345e832e645bdd",
    )
    assert_equal(
        hex_encode(
            checksum_digest(
                bytes_of(
                    " C+=%雪 9C%9C+c1é1 aB%1+caé+b1?B=cCb=aB?Bé90b/9ac=0 9B%Caé 1?bAéc"
                ),
                "sha1",
            )
        ),
        "a1a9374e35c480aa69b4314f265f475e0d494cb9",
    )
    assert_equal(
        hex_encode(
            checksum_digest(
                bytes_of(
                    " C+=%雪 9C%9C+c1é1 aB%1+caé+b1?B=cCb=aB?Bé90b/9ac=0 9B%Caé 1?bAéc"
                ),
                "crc32",
            )
        ),
        "7c42a03e",
    )
    assert_equal(
        hex_encode(
            checksum_digest(
                bytes_of(
                    " C+=%雪 9C%9C+c1é1 aB%1+caé+b1?B=cCb=aB?Bé90b/9ac=0 9B%Caé 1?bAéc"
                ),
                "crc32c",
            )
        ),
        "529940f8",
    )
    assert_equal(
        hex_encode(
            checksum_digest(
                bytes_of(
                    "=? a%9%雪=/C0?A/9Ca10 cCA+b%=bé?雪101+9AB9/Abbé?/9+9%A%%==1C+éB=999"
                ),
                "sha256",
            )
        ),
        "d0aef0dd46efecbcf3e29e1928a27a9d49f9b40cdb1f2a69cf9c9717c4b59726",
    )
    assert_equal(
        hex_encode(
            checksum_digest(
                bytes_of(
                    "=? a%9%雪=/C0?A/9Ca10 cCA+b%=bé?雪101+9AB9/Abbé?/9+9%A%%==1C+éB=999"
                ),
                "sha1",
            )
        ),
        "5f9b179ef890c138d8536f95538c933814e1ff09",
    )
    assert_equal(
        hex_encode(
            checksum_digest(
                bytes_of(
                    "=? a%9%雪=/C0?A/9Ca10 cCA+b%=bé?雪101+9AB9/Abbé?/9+9%A%%==1C+éB=999"
                ),
                "crc32",
            )
        ),
        "1b0e4f7a",
    )
    assert_equal(
        hex_encode(
            checksum_digest(
                bytes_of(
                    "=? a%9%雪=/C0?A/9Ca10 cCA+b%=bé?雪101+9AB9/Abbé?/9+9%A%%==1C+éB=999"
                ),
                "crc32c",
            )
        ),
        "02340035",
    )
    assert_equal(
        hex_encode(
            checksum_digest(
                bytes_of(
                    "1%Ac+雪 9Cé aba1é/9AB雪b bc%1%bCCC+%0AC %bé=éb=é9Ba9雪aCéa99éba/cc%?B=A 00C é1?cac9/?CC 9 éa/9/1Aca/BBb/+aBB0Bb?é9aab=9%C雪b1雪 =CA%?BC/a1bbaaC/1/=雪A雪%1%cc1Aé1%ébé%b/雪9=bABC%++b/ /%aa 9ac雪c ?/C0é?19+雪BB00éCAA1 0雪?11+céb?CbaAb?=A+=+雪C=B?éé%C+b+0=b%A?9雪?a%CaAb 9"
                ),
                "sha256",
            )
        ),
        "51ae3d779e7fd075bfc950874921f9bc59f8cb7514144192e19d8e20e1ec9dd2",
    )
    assert_equal(
        hex_encode(
            checksum_digest(
                bytes_of(
                    "1%Ac+雪 9Cé aba1é/9AB雪b bc%1%bCCC+%0AC %bé=éb=é9Ba9雪aCéa99éba/cc%?B=A 00C é1?cac9/?CC 9 éa/9/1Aca/BBb/+aBB0Bb?é9aab=9%C雪b1雪 =CA%?BC/a1bbaaC/1/=雪A雪%1%cc1Aé1%ébé%b/雪9=bABC%++b/ /%aa 9ac雪c ?/C0é?19+雪BB00éCAA1 0雪?11+céb?CbaAb?=A+=+雪C=B?éé%C+b+0=b%A?9雪?a%CaAb 9"
                ),
                "sha1",
            )
        ),
        "25a2c1874c26a4d72ac02df3985794add891bd9b",
    )
    assert_equal(
        hex_encode(
            checksum_digest(
                bytes_of(
                    "1%Ac+雪 9Cé aba1é/9AB雪b bc%1%bCCC+%0AC %bé=éb=é9Ba9雪aCéa99éba/cc%?B=A 00C é1?cac9/?CC 9 éa/9/1Aca/BBb/+aBB0Bb?é9aab=9%C雪b1雪 =CA%?BC/a1bbaaC/1/=雪A雪%1%cc1Aé1%ébé%b/雪9=bABC%++b/ /%aa 9ac雪c ?/C0é?19+雪BB00éCAA1 0雪?11+céb?CbaAb?=A+=+雪C=B?éé%C+b+0=b%A?9雪?a%CaAb 9"
                ),
                "crc32",
            )
        ),
        "2f932231",
    )
    assert_equal(
        hex_encode(
            checksum_digest(
                bytes_of(
                    "1%Ac+雪 9Cé aba1é/9AB雪b bc%1%bCCC+%0AC %bé=éb=é9Ba9雪aCéa99éba/cc%?B=A 00C é1?cac9/?CC 9 éa/9/1Aca/BBb/+aBB0Bb?é9aab=9%C雪b1雪 =CA%?BC/a1bbaaC/1/=雪A雪%1%cc1Aé1%ébé%b/雪9=bABC%++b/ /%aa 9ac雪c ?/C0é?19+雪BB00éCAA1 0雪?11+céb?CbaAb?=A+=+雪C=B?éé%C+b+0=b%A?9雪?a%CaAb 9"
                ),
                "crc32c",
            )
        ),
        "d6be02e0",
    )
    assert_equal(
        hex_encode(
            checksum_digest(
                bytes_of(
                    "0?+=%9?1éb 0/é 9CC%0c=雪/é091雪  0 c=é雪éBbC?/B?? +aébB=A+ ?=雪/bba aCéAb雪bB1++0/%%++ab=?C AA? ?b+éB%+0=C1?Cé0acéA0 ba?a//1a1 /??B%/%b00 AaBé%a雪+/c% C==+雪?A9CBcb c9雪 1雪Bc%bA%cacaA0B?A=C0+A1=%+B01éC9 %9?aC + bAA=é1?+B 雪c%雪1+?1B雪/??C雪caB /9a%+10 09c/B=1c雪++b c雪?"
                ),
                "sha256",
            )
        ),
        "b74d23211a9e484935e8d041a47574f66eb833812c65e8c056a195438823af2e",
    )
    assert_equal(
        hex_encode(
            checksum_digest(
                bytes_of(
                    "0?+=%9?1éb 0/é 9CC%0c=雪/é091雪  0 c=é雪éBbC?/B?? +aébB=A+ ?=雪/bba aCéAb雪bB1++0/%%++ab=?C AA? ?b+éB%+0=C1?Cé0acéA0 ba?a//1a1 /??B%/%b00 AaBé%a雪+/c% C==+雪?A9CBcb c9雪 1雪Bc%bA%cacaA0B?A=C0+A1=%+B01éC9 %9?aC + bAA=é1?+B 雪c%雪1+?1B雪/??C雪caB /9a%+10 09c/B=1c雪++b c雪?"
                ),
                "sha1",
            )
        ),
        "e6d912bf2fac328f85f24365e98135b6517f9126",
    )
    assert_equal(
        hex_encode(
            checksum_digest(
                bytes_of(
                    "0?+=%9?1éb 0/é 9CC%0c=雪/é091雪  0 c=é雪éBbC?/B?? +aébB=A+ ?=雪/bba aCéAb雪bB1++0/%%++ab=?C AA? ?b+éB%+0=C1?Cé0acéA0 ba?a//1a1 /??B%/%b00 AaBé%a雪+/c% C==+雪?A9CBcb c9雪 1雪Bc%bA%cacaA0B?A=C0+A1=%+B01éC9 %9?aC + bAA=é1?+B 雪c%雪1+?1B雪/??C雪caB /9a%+10 09c/B=1c雪++b c雪?"
                ),
                "crc32",
            )
        ),
        "f5b3cdfe",
    )
    assert_equal(
        hex_encode(
            checksum_digest(
                bytes_of(
                    "0?+=%9?1éb 0/é 9CC%0c=雪/é091雪  0 c=é雪éBbC?/B?? +aébB=A+ ?=雪/bba aCéAb雪bB1++0/%%++ab=?C AA? ?b+éB%+0=C1?Cé0acéA0 ba?a//1a1 /??B%/%b00 AaBé%a雪+/c% C==+雪?A9CBcb c9雪 1雪Bc%bA%cacaA0B?A=C0+A1=%+B01éC9 %9?aC + bAA=é1?+B 雪c%雪1+?1B雪/??C雪caB /9a%+10 09c/B=1c雪++b c雪?"
                ),
                "crc32c",
            )
        ),
        "d58095e5",
    )
    assert_equal(
        hex_encode(
            checksum_digest(
                bytes_of(
                    "c/A雪é雪+ 9a%B=+ 1+b%+%C/é%=é 0+909?ACéA /b+0éB0/1雪雪1===a=雪雪/+雪雪?90aC=?éA=ab雪c 雪Cb=/1%c% cC=9c c /A+0==A a0éCb?/0éAcC=0%1é9aBB =9/雪CaB雪éaAB==Cé/a=A?雪 雪9雪/A雪é= B9+A%%é=B/ Bb1雪+?B90/ éAa a éa é雪9?%// c/A1%é++Bb=Bcbcc%B é雪b雪/b09/=BBA9CB+a?C9%=/BB1/?=a??%1A/=A  c+AC1ccA91=0B雪A=b雪=C?1+c/=a=a?+A+% cA+1+ccC9 +9ba00AccB1雪A//ab9?A/é?c1a雪aC雪%?Bé雪0+Ac1雪雪雪 Cb A%CAa1雪C+雪/béb9+ 雪BCCC==+ c9b9雪==?0=0%bB=雪A0a0aCb1?雪B%10+A%c10éa%Ba/C?0Ca雪9?%雪雪  é +ébé?bA+0+C?ACébb 9ééBC bC%+1aBBb éé1Cé/a=c/AA/ A雪/ébAAA?+雪/ %CB  A/A?aa雪B90a0b= A1%é+c++1C1é+9 Cc=0/éA 90?=c/=aa1ébB cB A%雪 %A 1c1a/ =9C?雪éA=雪ac0CCAC é 0?éc?%cé9a /cc/c==éa11?=?a%%C%0雪+0é 9=?雪?雪%=éé?C ?Cc é%?B?+cB///9B9A9 A雪%?A=b/1aéBC 1é+éBA%雪=+?+雪CBb=%/Bb%c===B9雪%/a % bAé雪00bbb雪é=?91/?1é1bC雪/é===0=1A10 =é?+ac%0B1+ca/?9雪+CB=% %é9a+cB/ Cb雪9/Bé%9?9?/a9é+/b é?é0A=c雪c9BBé? é% C+B00bbé雪 a雪1cCC/1雪a+B++0BbBc雪C0/9CB/AB011ca=/=0%?é= /雪%%9 ?9aaC%=0a0%c/ A9/a9AB/a990cbééA?/91C+ 雪+éB0==c%%b+A/雪bBB???=%0?/abé9雪a09% % 雪雪%雪雪C=é1%b雪B雪0Cb99 c=1A/é雪9éBB0%b9+/B0aA雪??éé  1A9/1C1A é b%雪?é=abb9Aéb1aCC/1??"
                ),
                "sha256",
            )
        ),
        "dab035562a85f7cb47ccbe0943fd871936831db953da70672b6357c9141904b5",
    )
    assert_equal(
        hex_encode(
            checksum_digest(
                bytes_of(
                    "c/A雪é雪+ 9a%B=+ 1+b%+%C/é%=é 0+909?ACéA /b+0éB0/1雪雪1===a=雪雪/+雪雪?90aC=?éA=ab雪c 雪Cb=/1%c% cC=9c c /A+0==A a0éCb?/0éAcC=0%1é9aBB =9/雪CaB雪éaAB==Cé/a=A?雪 雪9雪/A雪é= B9+A%%é=B/ Bb1雪+?B90/ éAa a éa é雪9?%// c/A1%é++Bb=Bcbcc%B é雪b雪/b09/=BBA9CB+a?C9%=/BB1/?=a??%1A/=A  c+AC1ccA91=0B雪A=b雪=C?1+c/=a=a?+A+% cA+1+ccC9 +9ba00AccB1雪A//ab9?A/é?c1a雪aC雪%?Bé雪0+Ac1雪雪雪 Cb A%CAa1雪C+雪/béb9+ 雪BCCC==+ c9b9雪==?0=0%bB=雪A0a0aCb1?雪B%10+A%c10éa%Ba/C?0Ca雪9?%雪雪  é +ébé?bA+0+C?ACébb 9ééBC bC%+1aBBb éé1Cé/a=c/AA/ A雪/ébAAA?+雪/ %CB  A/A?aa雪B90a0b= A1%é+c++1C1é+9 Cc=0/éA 90?=c/=aa1ébB cB A%雪 %A 1c1a/ =9C?雪éA=雪ac0CCAC é 0?éc?%cé9a /cc/c==éa11?=?a%%C%0雪+0é 9=?雪?雪%=éé?C ?Cc é%?B?+cB///9B9A9 A雪%?A=b/1aéBC 1é+éBA%雪=+?+雪CBb=%/Bb%c===B9雪%/a % bAé雪00bbb雪é=?91/?1é1bC雪/é===0=1A10 =é?+ac%0B1+ca/?9雪+CB=% %é9a+cB/ Cb雪9/Bé%9?9?/a9é+/b é?é0A=c雪c9BBé? é% C+B00bbé雪 a雪1cCC/1雪a+B++0BbBc雪C0/9CB/AB011ca=/=0%?é= /雪%%9 ?9aaC%=0a0%c/ A9/a9AB/a990cbééA?/91C+ 雪+éB0==c%%b+A/雪bBB???=%0?/abé9雪a09% % 雪雪%雪雪C=é1%b雪B雪0Cb99 c=1A/é雪9éBB0%b9+/B0aA雪??éé  1A9/1C1A é b%雪?é=abb9Aéb1aCC/1??"
                ),
                "sha1",
            )
        ),
        "5e8ac03bd29b47646a0688332110e0dc8bd0cbcc",
    )
    assert_equal(
        hex_encode(
            checksum_digest(
                bytes_of(
                    "c/A雪é雪+ 9a%B=+ 1+b%+%C/é%=é 0+909?ACéA /b+0éB0/1雪雪1===a=雪雪/+雪雪?90aC=?éA=ab雪c 雪Cb=/1%c% cC=9c c /A+0==A a0éCb?/0éAcC=0%1é9aBB =9/雪CaB雪éaAB==Cé/a=A?雪 雪9雪/A雪é= B9+A%%é=B/ Bb1雪+?B90/ éAa a éa é雪9?%// c/A1%é++Bb=Bcbcc%B é雪b雪/b09/=BBA9CB+a?C9%=/BB1/?=a??%1A/=A  c+AC1ccA91=0B雪A=b雪=C?1+c/=a=a?+A+% cA+1+ccC9 +9ba00AccB1雪A//ab9?A/é?c1a雪aC雪%?Bé雪0+Ac1雪雪雪 Cb A%CAa1雪C+雪/béb9+ 雪BCCC==+ c9b9雪==?0=0%bB=雪A0a0aCb1?雪B%10+A%c10éa%Ba/C?0Ca雪9?%雪雪  é +ébé?bA+0+C?ACébb 9ééBC bC%+1aBBb éé1Cé/a=c/AA/ A雪/ébAAA?+雪/ %CB  A/A?aa雪B90a0b= A1%é+c++1C1é+9 Cc=0/éA 90?=c/=aa1ébB cB A%雪 %A 1c1a/ =9C?雪éA=雪ac0CCAC é 0?éc?%cé9a /cc/c==éa11?=?a%%C%0雪+0é 9=?雪?雪%=éé?C ?Cc é%?B?+cB///9B9A9 A雪%?A=b/1aéBC 1é+éBA%雪=+?+雪CBb=%/Bb%c===B9雪%/a % bAé雪00bbb雪é=?91/?1é1bC雪/é===0=1A10 =é?+ac%0B1+ca/?9雪+CB=% %é9a+cB/ Cb雪9/Bé%9?9?/a9é+/b é?é0A=c雪c9BBé? é% C+B00bbé雪 a雪1cCC/1雪a+B++0BbBc雪C0/9CB/AB011ca=/=0%?é= /雪%%9 ?9aaC%=0a0%c/ A9/a9AB/a990cbééA?/91C+ 雪+éB0==c%%b+A/雪bBB???=%0?/abé9雪a09% % 雪雪%雪雪C=é1%b雪B雪0Cb99 c=1A/é雪9éBB0%b9+/B0aA雪??éé  1A9/1C1A é b%雪?é=abb9Aéb1aCC/1??"
                ),
                "crc32",
            )
        ),
        "47ac9031",
    )
    assert_equal(
        hex_encode(
            checksum_digest(
                bytes_of(
                    "c/A雪é雪+ 9a%B=+ 1+b%+%C/é%=é 0+909?ACéA /b+0éB0/1雪雪1===a=雪雪/+雪雪?90aC=?éA=ab雪c 雪Cb=/1%c% cC=9c c /A+0==A a0éCb?/0éAcC=0%1é9aBB =9/雪CaB雪éaAB==Cé/a=A?雪 雪9雪/A雪é= B9+A%%é=B/ Bb1雪+?B90/ éAa a éa é雪9?%// c/A1%é++Bb=Bcbcc%B é雪b雪/b09/=BBA9CB+a?C9%=/BB1/?=a??%1A/=A  c+AC1ccA91=0B雪A=b雪=C?1+c/=a=a?+A+% cA+1+ccC9 +9ba00AccB1雪A//ab9?A/é?c1a雪aC雪%?Bé雪0+Ac1雪雪雪 Cb A%CAa1雪C+雪/béb9+ 雪BCCC==+ c9b9雪==?0=0%bB=雪A0a0aCb1?雪B%10+A%c10éa%Ba/C?0Ca雪9?%雪雪  é +ébé?bA+0+C?ACébb 9ééBC bC%+1aBBb éé1Cé/a=c/AA/ A雪/ébAAA?+雪/ %CB  A/A?aa雪B90a0b= A1%é+c++1C1é+9 Cc=0/éA 90?=c/=aa1ébB cB A%雪 %A 1c1a/ =9C?雪éA=雪ac0CCAC é 0?éc?%cé9a /cc/c==éa11?=?a%%C%0雪+0é 9=?雪?雪%=éé?C ?Cc é%?B?+cB///9B9A9 A雪%?A=b/1aéBC 1é+éBA%雪=+?+雪CBb=%/Bb%c===B9雪%/a % bAé雪00bbb雪é=?91/?1é1bC雪/é===0=1A10 =é?+ac%0B1+ca/?9雪+CB=% %é9a+cB/ Cb雪9/Bé%9?9?/a9é+/b é?é0A=c雪c9BBé? é% C+B00bbé雪 a雪1cCC/1雪a+B++0BbBc雪C0/9CB/AB011ca=/=0%?é= /雪%%9 ?9aaC%=0a0%c/ A9/a9AB/a990cbééA?/91C+ 雪+éB0==c%%b+A/雪bBB???=%0?/abé9雪a09% % 雪雪%雪雪C=é1%b雪B雪0Cb99 c=1A/é雪9éBB0%b9+/B0aA雪??éé  1A9/1C1A é b%雪?é=abb9Aéb1aCC/1??"
                ),
                "crc32c",
            )
        ),
        "deb214d6",
    )
