class KaTeXInjector {
  static const _cdnBase = 'https://cdn.jsdelivr.net/npm/katex@0.16.11/dist';

  static const _cdnCss = '$_cdnBase/katex.min.css';
  static const _cdnJs = '$_cdnBase/katex.min.js';
  static const _cdnAutoRender = '$_cdnBase/contrib/auto-render.min.js';

  static String inject(String html) {
    var result = html;

    final cssPattern = RegExp(r'(?:\.\./)*katex/katex\.min\.css');
    final jsPattern = RegExp(r'(?:\.\./)*katex/katex\.min\.js');
    final arPattern = RegExp(r'(?:\.\./)*katex/auto-render\.min\.js');

    result = result.replaceAll(cssPattern, _cdnCss);
    result = result.replaceAll(jsPattern, _cdnJs);
    result = result.replaceAll(arPattern, _cdnAutoRender);

    final hasKatexCss = result.contains('katex.min.css');
    final hasKatexJs = result.contains('katex.min.js');

    final buffer = StringBuffer();
    if (!hasKatexCss) {
      buffer.writeln('<link rel="stylesheet" href="$_cdnCss">');
    }
    if (!hasKatexJs) {
      buffer.writeln('<script src="$_cdnJs"></script>');
      buffer.writeln('<script src="$_cdnAutoRender"></script>');
    }

    buffer.writeln('''
<script>
(function(){
  var _savedOriginals=new Map();

  function saveAllOriginals(){
    _savedOriginals.clear();
    var w=document.createTreeWalker(document.body,NodeFilter.SHOW_TEXT,null,false);
    while(w.nextNode()){
      var tn=w.currentNode;
      if(tn.nodeValue&&tn.nodeValue.trim()&&tn.parentNode){
        var p=tn.parentNode;
        if(p.tagName==='SCRIPT'||p.tagName==='STYLE') continue;
        _savedOriginals.set(tn,tn.nodeValue);
      }
    }
  }

  function fixEmDashes(root){
    if(!root) root=document.body;
    if(!root) return;
    var w=document.createTreeWalker(root,NodeFilter.SHOW_TEXT,null,false);
    var nodes=[];
    while(w.nextNode()) nodes.push(w.currentNode);
    for(var i=0;i<nodes.length;i++){
      var tn=nodes[i];
      if(!tn.nodeValue) continue;
      var p=tn.parentNode;
      if(p&&(p.tagName==='SCRIPT'||p.tagName==='STYLE')) continue;
      if(p&&p.classList&&(p.classList.contains('katex')||p.getAttribute('data-mr'))) continue;
      var t=tn.nodeValue;
      var orig=t;
      t=t.replace(/[\\u2014\\u2013]/g,' - ');
      t=t.replace(/\\ufffd/g,' - ');
      t=t.replace(/  +/g,' ');
      if(t!==orig) tn.nodeValue=t;
    }
  }

  function cleanupFalseKaTeX(){
    var spans=document.querySelectorAll('span[data-mr]');
    for(var i=0;i<spans.length;i++){
      var span=spans[i];
      var txt=span.textContent||'';
      var stripped=txt.replace(/\\s/g,'');
      if(stripped.length===0) continue;
      var letters=txt.replace(/[^a-zA-Z]/g,'').length;
      var ratio=letters/stripped.length;
      if(ratio>0.55){
        var parent=span.parentNode;
        if(parent) parent.replaceChild(document.createTextNode(txt),span);
      }
    }
    var katexErrors=document.querySelectorAll('.katex-error');
    for(var j=0;j<katexErrors.length;j++){
      var el=katexErrors[j];
      var p2=el.parentNode;
      if(p2) p2.replaceChild(document.createTextNode(el.textContent||''),el);
    }
  }

  function runAll(){
    fixEmDashes();
    cleanupFalseKaTeX();
  }

  var _cleanupObserver=new MutationObserver(function(mutations){
    for(var i=0;i<mutations.length;i++){
      var added=mutations[i].addedNodes;
      for(var j=0;j<added.length;j++){
        var n=added[j];
        if(n.nodeType===1){
          if(n.classList&&n.classList.contains('katex')){
            var parent=n.parentNode;
            if(parent&&parent.getAttribute&&parent.getAttribute('data-mr')){
              var txt=parent.textContent||'';
              var stripped=txt.replace(/\\s/g,'');
              if(stripped.length>0){
                var letters=txt.replace(/[^a-zA-Z]/g,'').length;
                if(letters/stripped.length>0.55){
                  parent.parentNode.replaceChild(document.createTextNode(txt),parent);
                }
              }
            }
          }
          if(n.querySelectorAll){
            var katexEls=n.querySelectorAll('.katex-error');
            for(var k=0;k<katexEls.length;k++){
              var el=katexEls[k];
              if(el.parentNode) el.parentNode.replaceChild(document.createTextNode(el.textContent||''),el);
            }
          }
        }
      }
    }
  });

  function tryRender(attempt){
    if(typeof katex!=='undefined' && typeof renderMathNow==='function'){
      saveAllOriginals();
      try{ renderMathNow(); }catch(e){}
      setTimeout(runAll,50);
      setTimeout(runAll,300);
      setTimeout(runAll,800);
      setTimeout(runAll,2000);
      try{ _cleanupObserver.observe(document.body,{childList:true,subtree:true}); }catch(e){}
      return;
    }
    if(attempt<60) setTimeout(function(){ tryRender(attempt+1); },100);
  }

  if(document.readyState==='loading'){
    document.addEventListener('DOMContentLoaded',function(){
      setTimeout(function(){ tryRender(0); },100);
    });
  }else{
    setTimeout(function(){ tryRender(0); },100);
  }
})();
</script>''');

    final injection = buffer.toString();
    if (result.contains('</head>')) {
      result = result.replaceFirst('</head>', '$injection</head>');
    } else if (result.contains('<body')) {
      result = result.replaceFirst(RegExp(r'<body[^>]*>'), '$injection\$0');
    } else {
      result = '$injection$result';
    }

    return result;
  }
}
