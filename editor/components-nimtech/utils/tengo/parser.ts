import { LRParser, LocalTokenGroup } from '@lezer/lr'
import { semicolon, trackTokens } from './tokens'
import { tengoHighlighting } from './highlight'
const spec_identifier = Object.assign(Object.create(null) as Record<string, number>, {
  true: 210,
  false: 210,
  undefined: 212,
  func: 90,
  error: 102,
  immutable: 106,
  if: 140,
  else: 142,
  for: 146,
  in: 150,
  return: 158,
  break: 162,
  continue: 166
})
export const parser = LRParser.deserialize({
  version: 14,
  states:
    "=vO!pQQOOP!wOQOOOOQP'#Cc'#CcOOQP'#Cd'#CdO!|QTO'#CeOOQO'#C{'#C{OOQO'#C|'#C|OOQO'#C}'#C}O&WQQO'#ChO&_QQO'#D_OOQP'#Eg'#EgO&fQTO'#EeOOQP'#Ef'#EfO(cQQO'#DiOOQP'#Ee'#EeO*}QTO'#C`OOQP'#Ed'#EdOOQP'#Ec'#EcOOQP'#Eb'#EbO+XQRO'#ETOOQO'#ET'#ETO+aQQO'#EaQOQQOOO+kQQO'#DXO+rQQO'#DYO+wQQO'#D`O+|QQO'#DbO,RQQO'#DoO(cQQO'#DsO-UQQO'#DvO-`QRO'#D|OOQP'#EO'#EOOOQP'#EQ'#EQP-mOpO'#C^POOO)C@P)C@POOQP'#Ce'#CeO-xQQO'#CkO/tQTO'#EmOOQP'#En'#EnO+kQQO'#CzOOQP'#Em'#EmO1xQSO'#EkOOQP'#El'#ElOOQO'#Ek'#EkO2YQQO,59SO2_QQO,59yO2dQQO,5:OO2iQWO,5:QO2sQQO'#DhOOQP,5:R,5:ROOQP,5:T,5:TOOQO'#DP'#DPOOQO'#DQ'#DQOOQO'#DR'#DROOQO'#DS'#DSOOQO'#DT'#DTOOQO'#DU'#DUO(cQQO,5:UO(cQQO,5:UO(cQQO,5:UO(cQQO,5:UO(cQQO,5:UO+kQQO,5:VO+kQQO,5:WOOQP,5:],5:]OOQO'#FV'#FVOOQO,5:o,5:oOOQO-E8R-E8RO2}QSO,59sO3UQQO,59tO+kQQO,59zO+kQQO,59|O+kQQO,5:ZO3aQSO,5:_O4tQSO,5:bO4{QQO'#DzO5SQQO'#DzO5XQQO'#DoOOQP,5:b,5:bO5dQQO,5:bO5iQTO,5:hPOOO'#ES'#ESP5sOpO,58xPOOO,58x,58xOOQP'#Cm'#CmOOQO'#Eo'#EoO6OQQO'#EoO6WQQO,59VO6]QWO'#ClO2dQQO,59]O6bQWO,59`O2sQQO'#CxOOQP,59a,59aOOQP,59f,59fO+kQQO,59jO+kQQO,59jO+kQQO,59jO+kQQO,59jO+kQQO,59jO6lQQO,5;VO+kQQO,59qO6zQQO,5;VOOQP1G.n1G.nOOQP1G/e1G/eOOQP1G/j1G/jO7[Q`O'#EmO8sQ`O1G/kO8}QQO1G/lO9XQQO,5:SOOQP1G/p1G/pO:wQTO1G/pO;XQTO1G/pO=YQTO1G/pO=aQTO1G/pO=hQ`O1G/qO=oQTO1G/rOOQP1G/_1G/_OOQO'#D]'#D]OOQO'#D['#D[OOQO'#FU'#FUO=|QQO'#FUO>UQQO1G/`O>ZQSO1G/fO>bQSO1G/hO>iQTO1G/uO>vQRO1G/yOOQP1G/|1G/|O?RQSO,5:fO?YQQO,5:fO?aQQO,5:fO+kQQO,5:dO?hQQO,5:dPOOO-E8Q-E8QPOOO1G.d1G.dO?mQQO,5;ZO?xQQO,5;ZOOQP1G.q1G.qO+kQQO,59WOOQP1G.w1G.wO@QQQO1G.zO@[Q`O1G.yO@fQQO,59dOOQP1G/U1G/UOBeQTO1G/UOBuQTO1G/UOEVQTO1G/UOE^QTO1G/UOOQO-E8T-E8TOEeQQO1G0qOEuQ`O1G/]OE|QSO,5:qOOQP7+%V7+%VOF^QQO7+%WOFhQSO7+%WOOQP7+%W7+%WOOQP1G/n1G/nOFoQQO1G/nO+kQQO7+%]OFtQQO,5;pOF|QQO,5;pO5dQQO7+$zOOQP7+%Q7+%QOOQP7+%S7+%SOGUQQO7+%eOG^QQO1G0QOOQO1G0Q1G0QOGeQSO1G0QOGlQSO1G0OOGsQQO1G0OOOQO,5:p,5:pOGxQWO'#CpOG}QQO1G0uOOQO-E8S-E8SOHYQSO1G.rOOQP7+$f7+$fOHdQSO7+$fOOQP7+$e7+$eOHkQQO7+$fOOQP1G/O1G/OOHuQQO1G/OP+kQQO'#EVO+kQQO7+$wOJUQ`O1G/UOJfQ`O1G/UOLZQ`O1G/UOLbQ`O1G/UOLiQSO<<HrOOQP<<Hr<<HrOOQP7+%Y7+%YOLpQTO<<HwOOQO'#D^'#D^OOQO,5:r,5:rOMWQQO1G1[OOQO-E8U-E8UOOQP<<Hf<<HfOOQP<<IP<<IPOOQO7+%l7+%lOM`QQO7+%lO+kQQO7+%jO+kQQO,59[PMgQQO'#EUOOQP<<HQ<<HQOMoQSO<<HQOOQP7+$j7+$jOMvQTO<<HcOOQPAN>^AN>^P?hQQO'#EWOOQO<<IW<<IWONmQSO<<IUONtQSO1G.vOOQPAN=lAN=lO! OQ`O<<HcO+kQQO'#CzO+kQQO,59jO+kQQO,59jO+kQQO,59jO+kQQO,59jO+kQQO,59jO+kQQO7+$wO! YQ`O1G/]O+kQQO,59q",
  stateData:
    '! g~O#OOSPOS#PPQ~OTYOUYOZWO^XOkgO}hO!TiO!VjO!hlO!kmO!odO!qnO!soO!upO#[SO#]QO#^RO#dTO#eTO#fUO#gVO~O!{#TP~P]O#PqO~OZXXfXXkXXzXX!aXX!bXX!d!PX!fXX!oXX!|XX#dXX#eXX#gXX#hXX#iXX#jXX#kXX#lXX#mXX#nXX#oXX#pXX#qXX#rXX#sXX#tXX#uXX#vXX#wXX^XXc!PX!m!PX~OTYOUYOZWO^tOc{OkgO}hO!TiO!VjO#[sO#]QO#^RO#dTO#eTO#fUO#gVO~OY#_P~P%SO]#TP~P]OZ!POf!OOk!QOz#XX!a#XX!b#XX!f#XX!o#XX!|#XX#d#XX#e#XX#g#XX#h#XX#i#XX#j#XX#k#XX#l#XX#m#XX#n#XX#o#XX#p#XX#q#XX#r#XX#s#XX#t#XX#u#XX#v#XX#w#XX^#XX~OTYOUYOZWOkgO}hO!TiO!VjO#[sO#]QO#^RO#dTO#eTO#fUO#gVO~Oz!`O!a!aO!b!aO!f!bO#dTO#eTO#g!VO#h!TO#i!TO#j!TO#k!UO#l!UO#m!UO#n!UO#o!VO#p!WO#q!WO#r!WO#s!WO#t!WO#u!WO#v!XO#w!YO!oSX~O!|SX^SX~P)aO!o!cO!|!cO~O!{#TX]#TX~P]O^tO~P(cOk!gO~Ok!hO~Ok!iO~O!d!jO~OTYOUYOZWOkgO}hO!TiO!VjO#[SO#]QO#^RO#dTO#eTO#fUO#gVO~O^XO!o!mO~P,WO^tO!o!pX!|!pX~P(cO#Q!sO#R!sO#S!uO~OU!zOc!wO#[!vO]#cP~OZ!|Of!{Ok!}OY#aXz#aX#d#aX#e#aX#g#aX#h#aX#i#aX#j#aX#k#aX#l#aX#m#aX#n#aX#o#aX#p#aX#q#aX#r#aX#s#aX#t#aX#u#aX#v#aX#w#aX~Oc#aXj#aX!o#aX!|#aXm#aX^#aX]#aX!a#aX!b#aX!f#aX~P.WOz#WO#dTO#eTO#g!VO#h!TO#i!TO#j!TO#k!UO#l!UO#m!UO#n!UO#o!VO#p!WO#q!WO#r!WO#s!WO#t!WO#u!WO#v!XO#w!YO~Oc#XOY#_Xj#_Xm#_X~P0hOY#YO~O]#ZO~O#[!vO~O^tOb#_O~P(cOj#_Pm#_P~P%SOj#hO~P0hOc#kO#[#iOj#xP~O^XOz!`O#dTO#eTO#g!VO#h!TO#i!TO#j!TO#k!UO#l!UO#m!UO#n!UO#o!VO#p!WO#q!WO#r!WO#s!WO#t!WO#u!WO#v!XO#w!YO~O^XO~P)aO!o#tO~P(cO!o#uO~Oc#wO!d!jO!m#vO~O^XO~O!o!pa!|!pa~P0hO#Q!sO#R!sO#S#yO~Oc#zO]#cX~O]#|O~Ob#}O~O^tOb$PO~P(cOc$YOY#_aj#_am#_a~O^tOY#_aj#_am#_a~P(cOb#aX~P.WOz%tO#dTO#eTO#g!VO#h!TO#i!TO#j!TO#k!UO#l!UO#m!UO#n!UO#o!VO#p!WO#q!WO#r!WO#s!WO#t!WO#u!WO#v!XO#w!YO~OY$]Ob$^O~P7cOY$`O^tO~P(cOj$aOm$bO~O#h!TO#i!TO#j!TO#k!UO#l!UO#m!UO#n!UOz!^i!a!^i!b!^i!f!^i!o!^i!|!^i#p!^i#q!^i#r!^i#s!^i#t!^i#u!^i#v!^i#w!^i^!^i~O#d!^i#e!^i#g!^i#o!^i~P9aO#dTO#eTO#g!VO#o!VO~P9aO#dTO#eTO#g!VO#h!TO#i!TO#j!TO#k!UO#l!UO#m!UO#n!UO#o!VO#p!WO#q!WO#r!WO#s!WO#t!WO#u!WOz!^i!a!^i!b!^i!f!^i!o!^i!|!^i#w!^i^!^i~O#v!^i~P;iO#v!XO~P;iOb$cO~P7cO!o!`i!|!`i^!`i~P0hOc$dOj#xX~Oj$fO~Oj$gO~P0hOj$hO~P0hO!o!ci!|!ci^!ci~P0hO!i$iO!o!gi!|!gi~O!o$jO~P3dO^!na~P,WO!o$jO~P(cO#[#iO~OU$pO#[!vO]#ca~Oc$qO]#ca~OY$tO^tO~P(cOY$vOb$wO~P7cOj$xOm$yO~O#h!TO#i!TO#j!TO#k!UO#l!UO#m!UO#n!UOYricrizri#pri#qri#rri#sri#tri#uri#vri#wrijri!ori!|rimri^ri]ri!ari!bri!fri~O#dri#eri#gri#ori~P@nO#dTO#eTO#g!VO#o!VO~P@nO#dTO#eTO#g!VO#h!TO#i!TO#j!TO#k!UO#l!UO#m!UO#n!UO#o!VO#p!WO#q!WO#r!WO#s!WO#t!WO#u!WOYricrizri#wrijri!ori!|rimri^ri]ri!ari!bri!fri~O#vri~PCVO#v!XO~PCVO^tOY#_ij#_im#_i~P(cOb${O~P7cOY!yac!yaj!yam!ya~P0hOY%RO^tO~P(cOY%RO~P0hOj%SO~O#[#iOj#xa~Oc%WOj#xa~O^XO!hlO~O^!ni~P,WO!o%]O~P3dO^!li~P0hO!m%^O~Ob%_O~OU$pO#[!vO]#ci~O]`ic`i~P0hOY%aO~P0hOY%aO^tO~P(cOj%cO~O#h!TO#i!TO#j!TO#k!UO#l!UO#m!UO#n!UOYribrizri#pri#qri#rri#sri#tri#uri#vri#wri~O#dri#eri#gri#ori~PHzO#dTO#eTO#g!VO#o!VO~PHzO#dTO#eTO#g!VO#h!TO#i!TO#j!TO#k!UO#l!UO#m!UO#n!UO#o!VO#p!WO#q!WO#r!WO#s!WO#t!WO#u!WOYribrizri#wri~O#vri~PJvO#v!XO~PJvOY%eO~P0hO!a!_y!b!_y!f!_y!o!_y!|!_y^!_y~P0hO#[#iOj#xi~O^!nq~P,WOU$pO#[!vO~OY%jO~P0hOYyycyyjyy!oyy!|yymyy^yy]yy!ayy!byy!fyy~P0hO^!ly~P0hO]dicdi~P0hOYyybyy~P7cOb%rO~P7cOP#iT#[T~',
  goto: "<Z#zPP#{P$OPP$X$X$XPP$XPP%e&a&dPP&r%eP%e%e%ePP&wP&{'w*V*V+g,a,a-b.`/Z0R+gP$X$XP0v0y1a1f$XP$XP1{1{1{1{2_2b2t2t$OPP$OP$OP3VPP3_P3dP3dP3_P3_P3_P3g3m3t3z4QPPPPPPPP4W4^4c4t5i5}6aPPP7o7x:U;S<QPPPPPPPPPPPPPPPPPPPP<T<WRrP_aOXem#t$j%]#eYOWX]eglmnw!P!Q!Z![!]!^!_!`!a!h!i!j!m!|!}#Q#R#S#T#U#W#X#_#t#u#v#}$P$Y$^$c$j$w$z${%]%^%_%l%m%n%o%p%q%r%t!svWgnw!P!Q!`!a!h!i!j!|!}#Q#R#S#T#U#W#X#_#v#}$P$Y$^$c$w$z${%^%_%l%m%n%o%p%q%r%tR!xtQ!ztQ#[!OQ$O!{V$p#z$q%`V$o#z$q%`T#Ou#]!sxWgnw!P!Q!`!a!h!i!j!|!}#Q#R#S#T#U#W#X#_#v#}$P$Y$^$c$w$z${%^%_%l%m%n%o%p%q%r%tp]OX]elm!Z![!]!^!_!m#t#u$j%]!YwWgnw!Q!a!h!i!j!}#Q#R#S#T#U#X#_#v#}$P$Y$^$c$w$z${%^%_`![_!k!l#c#d#e#s$lz#Ry!f!r#g#n#o#p$U$V$W$[$_$m$s$u%Q%T%b%d%h%ih%l!P!`!|#W%l%m%n%o%p%q%r%tc%n#^#f$Q$Z$}%O%P%k%sp]OX]elm!Z![!]!^!_!m#t#u$j%]!YwWgnw!Q!a!h!i!j!}#Q#R#S#T#U#X#_#v#}$P$Y$^$c$w$z${%^%_i%l!P!`!|#W%l%m%n%o%p%q%r%t!ozWgn!P!Q!`!a!h!i!j!|!}#Q#R#S#T#U#W#X#_#v#}$P$Y$^$c$w$z${%^%_%m%n%o%p%q%r%tb!Z_!k!l#b#c#d#e#s$l|#Qy!f!r#g#n#o#p$T$U$V$W$[$_$m$s$u%Q%T%b%d%h%ie%m#^#f$Q$Z$|$}%O%P%k%s`![_!k!l#c#d#e#s$lz#Ry!f!r#g#n#o#p$U$V$W$[$_$m$s$u%Q%T%b%d%h%ic%n#^#f$Q$Z$}%O%P%k%s^!]_!k!l#d#e#s$lx#Sy!f!r#g#n#o#p$V$W$[$_$m$s$u%Q%T%b%d%h%ia%o#^#f$Q$Z%O%P%k%s[!^_!k!l#e#s$lv#Ty!f!r#g#n#o#p$W$[$_$m$s$u%Q%T%b%d%h%i_%p#^#f$Q$Z%P%k%sY!__!k!l#s$lt#Uy!f!r#g#n#o#p$[$_$m$s$u%Q%T%b%d%h%i]%q#^#f$Q$Z%k%sR#l!g[kOXe#t$j%]Q!omQ#j!gQ$n#wV%U$d%W%fV%V$d%W%fUbOXeQ!pmQ#q!kS#r!l!qQ%Y$fR%Z$iq[OX]elm!Z![!]!^!_!m#t#u$j%]R!RZq^OX]elm!Z![!]!^!_!m#t#u$j%]o`OXelm!Z![!]!^!_!m#t#u$j%]UbOXeR%Z$iVbOXeR!qmQ!tqR#x!tSeOXR!eeQ#{!xR$r#{Q#VyR$X#VQ$e#lR%X$eQfOR}XVcOXeUbOXeQ!nmQ$k#tQ%[$jR%g%][_OXe#t$j%]Q!klQ!lmQ#a!ZQ#b![Q#c!]Q#d!^Q#e!_Q#s!mR$l#un`OXelm!Z![!]!^!_!m#t#u$j%]R!S]qZOX]elm!Z![!]!^!_!m#t#u$j%]p[OX]elm!Z![!]!^!_!m#t#u$j%]!svWgnw!P!Q!`!a!h!i!j!|!}#Q#R#S#T#U#W#X#_#v#}$P$Y$^$c$w$z${%^%_%l%m%n%o%p%q%r%tQ|WQ#`!QR$R!}UyW!Q!}Q!fgQ!rnQ#^!PQ#f!`Q#g!aQ#n!hQ#o!iQ#p!jQ$Q!|S$S#Q%mQ$T#RQ$U#SQ$V#TQ$W#UQ$Z#WU$[#X$Y$zQ$_#_Q$m#vQ$s#}Q$u$PQ$|%nQ$}%oQ%O%pQ%P%qQ%Q$^Q%T$cQ%b$wQ%d${Q%h%^Q%i%_Q%k%rR%s%t!nzWgn!P!Q!`!a!h!i!j!|!}#Q#R#S#T#U#W#X#_#v#}$P$Y$^$c$w$z${%^%_%m%n%o%p%q%r%tT#Pw%l!YuWgnw!Q!a!h!i!j!}#Q#R#S#T#U#X#_#v#}$P$Y$^$c$w$z${%^%_i#]!P!`!|#W%l%m%n%o%p%q%r%tR!ytR#m!gR!dc",
  nodeNames:
    '⚠ LineComment BlockComment Script ExprStatement Number String Bool Undefined VariableName ] [ ArrayLiteral } { MapLiteral MapEntry FieldName : , MapEntry SelectorExpr . IndexExpr SliceExpr CallExpr ) ( Arguments ... UnaryExpr ArithOp LogicOp BitOp BinaryExpr ArithOp BitOp BitOp CompareOp LogicOp LogicOp TernaryExpr ? ParenthesizedExpr FunctionLiteral func Parameter DefName Parameter Block ErrorExpr error ImmutableExpr immutable SelectorExpr IndexExpr SliceExpr CallExpr Arguments UnaryExpr BinaryExpr TernaryExpr Assignment = UpdateOp ShortVarDecl := IncDecStatement IncDecOp IfStatement if else ForStatement for ForInClause in ForCondClause ; ReturnStatement return BreakStatement break ContinueStatement continue',
  maxTerm: 133,
  context: trackTokens,
  nodeProps: [
    ['isolate', -2, 2, 6, ''],
    [
      'group',
      -10,
      4,
      49,
      62,
      65,
      67,
      69,
      72,
      78,
      80,
      82,
      'Statement',
      -18,
      5,
      6,
      7,
      8,
      9,
      12,
      15,
      21,
      23,
      24,
      25,
      30,
      34,
      41,
      43,
      44,
      50,
      52,
      'Expr'
    ],
    ['openedBy', 10, '[', 13, '{', 26, '('],
    ['closedBy', 11, ']', 14, '}', 27, ')']
  ],
  propSources: [tengoHighlighting],
  skippedNodes: [0, 1, 2, 84],
  repeatNodeCount: 5,
  tokenData:
    "4z~RuXY#fYZ#f]^#fpq#fqr#wrs$Uuv%|vw&Zxy&vyz&{z{'Q{|'Y|}'j}!O'o!O!P'z!P!Q)w!Q!R*s!R![+e![!]-i!]!^-v!^!_-{!_!`.e!`!a.r!a!b/[!c!}/a!}#O0R#P#Q0W#Q#R0]#R#S0e#S#T3v#T#o/a#o#p4`#p#q4e#q#r4u$g;'S/a;'S;=`/{<%lO/a~#kS#O~XY#fYZ#f]^#fpq#fn#|P#fY!_!`$Pd$UO#qd~$ZWU~OY$UZr$Urs$ss#O$U#O#P$x#P;'S$U;'S;=`%v<%lO$U~$xOU~~${RO;'S$U;'S;=`%U;=`O$U~%ZXU~OY$UZr$Urs$ss#O$U#O#P$x#P;'S$U;'S;=`%v;=`<%l$U<%lO$U~%yP;=`<%l$U~&RP#j~!_!`&U~&ZO!b~~&`R#m~vw&i!_!`&U#Q#R&n~&nO#v~~&sP#n~!_!`&U~&{Ok~~'QOj~~'VP#h~!_!`&U~'_Q#d~{|'e!_!`&U~'jO!f~~'oOc~~'tQ#e~}!O'e!_!`&U~(PRfd!O!P(Y!Q![(e#R#S)q~(]P!O!P(`~(eOm~Y(jSTY!Q![(e!g!h(v#R#S)q#X#Y(vY(yS{|)V}!O)V!Q![)`#R#S)kY)YQ!Q![)`#R#S)kY)eQTY!Q![)`#R#S)kY)nP!Q![)`Y)tP!Q![(e~)|R#i~z{*V!P!Q*[!_!`&U~*[O#P~~*aSP~OY*[Z;'S*[;'S;=`*m<%lO*[~*pP;=`<%l*[Y*xXTY!O!P(e!Q![+e!g!h(v!q!r,P!z!{,k#R#S+y#X#Y(v#c#d,P#l#m,kY+jTTY!O!P(e!Q![+e!g!h(v#R#S+y#X#Y(vY+|P!Q![+eY,SQ!Q!Y,Y#R#S,eY,_QTY!Q!Y,Y#R#S,eY,hP!Q!Y,YY,nS!Q![,z!c!i,z#R#S-]#T#Z,zY-PSTY!Q![,z!c!i,z#R#S-]#T#Z,zY-`R!Q![,z!c!i,z#T#Z,zn-nPbh!_!`-qU-vO!dU~-{O!o~~.QQ#r~!^!_.W!_!`.`~.]P#k~!_!`&U~.eO#s~~.jP!a~!_!`.m~.rO#p~~.wQ#t~!_!`.}!`!a/S~/SO#u~~/XP#l~!_!`&U~/aOz~~/fV#[~!Q![/a!c!}/a#R#S/a#T#o/a$g;'S/a;'S;=`/{<%lO/a~0OP;=`<%l/a~0WOZ~~0]OY~~0bP#g~!_!`&U~0jV#[~!Q![1P!c!}/a#R#S/a#T#o/a$g;'S/a;'S;=`/{<%lO/a~1W[TY#[~!O!P(e!Q![1P!c!g/a!g!h1|!h!}/a#R#S0e#T#X/a#X#Y1|#Y#o/a$g;'S/a;'S;=`/{<%lO/a~2RX#[~{|)V}!O)V!Q![2n!c!}/a#R#S3[#T#o/a$g;'S/a;'S;=`/{<%lO/a~2uVTY#[~!Q![2n!c!}/a#R#S3[#T#o/a$g;'S/a;'S;=`/{<%lO/a~3aV#[~!Q![2n!c!}/a#R#S/a#T#o/a$g;'S/a;'S;=`/{<%lO/a~3yTO#S3v#S#T$s#T;'S3v;'S;=`4Y<%lO3v~4]P;=`<%l3v~4eO^~~4jQ#o~!_!`&U#p#q4p~4uO#w~~4zO]~",
  tokenizers: [
    semicolon,
    1,
    2,
    3,
    4,
    new LocalTokenGroup('j~RQYZXz{^~^O#R~~aP!P!Qd~iO#S~~', 25, 94)
  ],
  topRules: { Script: [0, 3] },
  specialized: [{ term: 104, get: (value: string) => spec_identifier[value] ?? -1 }],
  tokenPrec: 2133
})
