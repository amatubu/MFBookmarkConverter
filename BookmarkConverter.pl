#!/usr/bin/perl

use strict;
use warnings;
use utf8;

use File::Basename;
use File::Copy;
use XML::LibXML qw( XML_ELEMENT_NODE );

# 世界測地系 (WGS84) から日本測地系 (TOKYO97) へ
# http://homepage3.nifty.com/Nowral/02_DATUM/02_DATUM.html
# より

# WGS 84 -> Tokyo
# Nowral
# 99/9/23
#
# 定数
my $pi  = 4 * atan2(1,1); # 円周率
my $rd  = $pi / 180;      # [ラジアン/度]

# データム諸元
# 変換元
# (WGS 84)
my $a = 6378137.0; # 6378137; # 赤道半径
my $f = 1 / 298.257223563; # 1 / 298.257223; # 扁平率
my $e2 = 2*$f - $f*$f; # 第1離心率

# 変換先
# (Tokyo)
my $a_ = 6378137.0 - 739.845; # 6377397.155;
my $f_ = 1/298.257223563 - 0.000010037483; # 1 / 299.152813;
my $e2_ = 2*$f_ - $f_*$f_;

# 並行移動量 [m]
# e.g. $x_ = $x + $dx etc.
# http://vldb.gsi.go.jp/pub/trns96/params/xyz2xyz.par
# より、WGS84 -> Tokyo97 の値

my $dx = +146.3360; # -148;
my $dy = -506.8320; # +507;
my $dz = -680.2540; # +681;


# ここからメイン

# boomark.dat から読み込み

my $in_file = $ARGV[0];

my $path = dirname( $in_file );
my $out_file = "$path/bookmark.dat";
copy( $in_file, $out_file );

`plutil -convert xml1 $out_file`;

my $parser = XML::LibXML->new;
my $doc = $parser->parse_file( $out_file );

my $root = $doc->documentElement();

# plist -> dict -> array の順に探す

my @array = $doc->findnodes( '/plist/dict/array' );

my @nodes;
for my $child ( $array[0]->childNodes() ) {
    next if $child->nodeType != XML_ELEMENT_NODE;
    push @nodes, $child;
}

# print $#nodes;

# print $nodes[0]->textContent;

# ブックマークのノードを探す

for my $node ( @nodes ) {
    my $class = getClass( $node );
    if ( $class eq 'MFMySpot' || $class eq 'MFGeneralSpot' ) {
        # ブックマークのノードを見つけた

        # 緯度、経度を得る

        my ( $lat, $lon, $lat_wgs, $lon_wgs );
        for my $keyNode ( $node->getElementsByTagName( 'key' ) ) {
            if ( $keyNode->textContent eq 'latitude' ) {
                my $valueNode = getNextElementNode( $keyNode );
                $lat_wgs = $valueNode->textContent;
#                print $lat;
            } elsif ( $keyNode->textContent eq 'longitude' ) {
                my $valueNode = getNextElementNode( $keyNode );
                $lon_wgs = $valueNode->textContent;
#                print $lon;
            } elsif ( $keyNode->textContent eq 'position.latitude' ) {
                my $valueNode = getNextElementNode( $keyNode );
                $lat = $valueNode->textContent / 921600;
            } elsif ( $keyNode->textContent eq 'position.longitude' ) {
                my $valueNode = getNextElementNode( $keyNode );
                $lon = $valueNode->textContent / 921600;
            }
        }

        if ( defined ( $lat_wgs ) && defined( $lon_wgs ) ) {
            # WGS84 -> TOKYO97 に変換

            ( $lat, $lon ) = wgs2tokyo( $lat_wgs, $lon_wgs );
        }

        if ( defined ( $lat ) && defined ( $lon ) ) {
            # 得られた緯度、経度をもとに、新しいタグを作る

            my $maplatKeyNode = XML::LibXML::Element->new( 'key' );
            $maplatKeyNode->addChild( $doc->createTextNode( 'maplat' ) );
            $node->appendChild( $maplatKeyNode );
            my $maplatValueNode = XML::LibXML::Element->new( 'real' );
            $maplatValueNode->addChild( $doc->createTextNode( int( $lat * 921600 + 0.5 ) ) );
            $node->appendChild( $maplatValueNode );

            my $maplonKeyNode = XML::LibXML::Element->new( 'key' );
            $maplonKeyNode->addChild( $doc->createTextNode( 'maplon' ) );
            $node->appendChild( $maplonKeyNode );
            my $maplonValueNode = XML::LibXML::Element->new( 'real' );
            $maplonValueNode->addChild( $doc->createTextNode( int( $lon * 921600 + 0.5 ) ) );
            $node->appendChild( $maplonValueNode );

#            print $node->toString(1);
        }

        # state タグを作る

        my $stateKeyNode = XML::LibXML::Element->new( 'key' );
        $stateKeyNode->addChild( $doc->createTextNode( 'state' ) );
        $node->appendChild( $stateKeyNode );
        my $stateValueNode = XML::LibXML::Element->new( 'integer' );
        $stateValueNode->addChild( $doc->createTextNode( '1' ) );
        $node->appendChild( $stateValueNode );
    }
}

# ブックマーククラスを修正する

for my $node ( @nodes ) {
    my ( $key ) = $node->getElementsByTagName( 'key' );
    if ( defined $key ) {
        my $keyName = $key->textContent;

        if ( $keyName eq '$classes' ) {
            my @classNameNodes = $node->getElementsByTagName( 'string' );
            for my $classNameNode ( @classNameNodes ) {
                if ( $classNameNode->textContent eq 'MFMySpot' ) {
                    replaceStringTag( $classNameNode, 'MFPoiMySpot' );
                } elsif ( $classNameNode->textContent eq 'MFSpot' ) {
                    replaceStringTag( $classNameNode, 'MFPoi' );
                } elsif ( $classNameNode->textContent eq 'MFGeneralSpot' ) {
                    replaceStringTag( $classNameNode, 'MFPoiMySpot' );
                }
            }
        }
    }
}

$doc->toFile( $out_file, 1 );

`plutil -convert binary1 $out_file`;

# ノードのクラスを調べる

sub getClass {
    my ( $node ) = @_;

    # 最初のキー

    my ( $key ) = $node->getElementsByTagName( 'key' );
    if ( defined $key ) {
        # 最初のキーの値が $class かどうか

        my $keyName = $key->textContent;
        if ( $keyName eq '$class' ) {
            # $class だったら、次のノードの integer からインデックスを探す

            my $value = getNextElementNode( $key );
            my ( $index ) = $value->getElementsByTagName( 'integer' );
            my $classNode = @nodes[$index->textContent];

            # 見つかったインデックスからキーを探す

            my @keyNodes = $classNode->getElementsByTagName( 'key' );
            if ( $#keyNodes > 0 ) {
                my $keyName = $keyNodes[0]->textContent;
                if ( $keyName eq '$classes' ) {
                    # $classes だったら、string タグを探す

                    my @classNames = $classNode->getElementsByTagName( 'string' );

                    # string タグの最初の要素がクラス名

                    return $classNames[0]->textContent;
                }
            }
        }
    }
}

# 次のエレメントノードを得る

sub getNextElementNode {
    my ( $node ) = @_;

    my $nextNode = $node;
    do {
        $nextNode = $nextNode->nextSibling;
    } while ( $nextNode->nodeType != XML_ELEMENT_NODE );

    return $nextNode;
}

# string タグの内容を置きかえる

sub replaceStringTag {
    my ( $node, $string ) = @_;

    my $newStringNode = XML::LibXML::Element->new( 'string' );
    $newStringNode->addChild( $doc->createTextNode( $string ) );
    my $parentNode = $node->getParentNode;
    $parentNode->replaceChild( $newStringNode, $node );
}

# 世界測地系⇒日本測地系

sub wgs2tokyo {
    my ( $lat_wgs, $lon_wgs ) = @_;

    my ( $x, $y, $z ) = llh2xyz( $lat_wgs, $lon_wgs, 0, $a, $e2 );
    my ( $lat, $lon ) = xyz2llh( $x + $dx, $y + $dy, $z + $dz, $a_, $e2_ );

    return ( $lat, $lon );
}

sub llh2xyz { # 楕円体座標 -> 直交座標
  my($b, $l, $h, $a, $e2) = @_;
  my($sb, $cb, $rn, $x, $y, $z);

  $b *= $rd;
  $l *= $rd;
  $sb = sin($b);
  $cb = cos($b);
  $rn = $a / sqrt(1-$e2*$sb*$sb);

  $x = ($rn+$h) * $cb * cos($l);
  $y = ($rn+$h) * $cb * sin($l);
  $z = ($rn*(1-$e2)+$h) * $sb;

  ($x, $y, $z);
}

sub xyz2llh { # 直交座標 -> 楕円体座標
  my($x, $y, $z, $a, $e2) = @_;
  my($bda, $p, $t, $st, $ct, $b, $l, $sb, $rn, $h);
  $bda = sqrt(1-$e2); # b/a

  $p = sqrt($x*$x+$y*$y);
  $t = atan2($z, $p*$bda);
  $st = sin($t);
  $ct = cos($t);
  $b = atan2($z+$e2*$a/$bda*$st*$st*$st, $p-$e2*$a*$ct*$ct*$ct);
  $l = atan2($y, $x);

  $sb = sin($b);
  $rn = $a / sqrt(1-$e2*$sb*$sb);
  $h = $p/cos($b) - $rn;

  ($b/$rd, $l/$rd, $h);
}

exit 0;

1;
