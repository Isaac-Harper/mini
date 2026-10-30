use cef::*;

use crate::{login::token, page_reply};

const PAGE_MARKDOWN_SCRIPT: &str = r#"(function(){
var token=__TOKEN__,request=__REQUEST__,signal=console.debug.bind(console);
var skipped={SCRIPT:1,STYLE:1,NOSCRIPT:1,TEMPLATE:1,NAV:1,FOOTER:1,ASIDE:1,IFRAME:1,SVG:1,CANVAS:1,BUTTON:1,SELECT:1,TEXTAREA:1,INPUT:1,DIALOG:1};
var blocks={P:1,H1:1,H2:1,H3:1,H4:1,H5:1,H6:1,UL:1,OL:1,PRE:1,BLOCKQUOTE:1,TABLE:1,HR:1,DIV:1,SECTION:1,ARTICLE:1,MAIN:1,HEADER:1,FIGURE:1,FIGCAPTION:1,DL:1,DT:1,DD:1,DETAILS:1,SUMMARY:1,ADDRESS:1,LI:1};
function absolute(url){try{return new URL(url,document.baseURI).href;}catch(error){return url;}}
function hidden(element){
if(skipped[element.tagName.toUpperCase()]||element.hidden||element.getAttribute('aria-hidden')==='true')return true;
var style=getComputedStyle(element);return style.display==='none'||style.visibility==='hidden';}
function wrap(text,mark){var trimmed=text.trim();return trimmed?mark+trimmed+mark:'';}
function inline(element){var out='';element.childNodes.forEach(function(child){out+=inlineNode(child);});return out;}
function inlineNode(node){
if(node.nodeType===3)return node.nodeValue.replace(/\s+/g,' ');
if(node.nodeType!==1||hidden(node))return '';
var tag=node.tagName.toUpperCase();
if(tag==='BR')return '  \n';
if(tag==='A'){var href=node.getAttribute('href'),text=inline(node).trim();
if(!href||!text||/^(javascript|data):/i.test(href))return text;
return '['+text+']('+absolute(href)+')';}
if(tag==='IMG'){var source=node.currentSrc||node.getAttribute('src');
return source&&!/^data:/i.test(source)?'!['+(node.getAttribute('alt')||'')+']('+absolute(source)+')':'';}
if(tag==='STRONG'||tag==='B')return wrap(inline(node),'**');
if(tag==='EM'||tag==='I')return wrap(inline(node),'*');
if(tag==='DEL'||tag==='S')return wrap(inline(node),'~~');
if(tag==='CODE'){var code=node.textContent;return code?'`'+code+'`':'';}
return inline(node);}
function container(element){
var parts=[],run='';
function flush(){var text=run.replace(/[ \t]+\n/g,'\n').trim();if(text)parts.push(text);run='';}
element.childNodes.forEach(function(child){
if(child.nodeType===3){run+=child.nodeValue.replace(/\s+/g,' ');return;}
if(child.nodeType!==1||hidden(child))return;
if(!blocks[child.tagName.toUpperCase()]){run+=inlineNode(child);return;}
flush();var markdown=block(child);if(markdown)parts.push(markdown);});
flush();return parts.join('\n\n');}
function block(element){
var tag=element.tagName.toUpperCase();
if(/^H[1-6]$/.test(tag)){var heading=inline(element).replace(/\s+/g,' ').trim();return heading?'######'.slice(0,Number(tag[1]))+' '+heading:'';}
if(tag==='P'||tag==='DT'||tag==='SUMMARY'||tag==='ADDRESS')return inline(element).replace(/[ \t]+\n/g,'\n').trim();
if(tag==='UL'||tag==='OL')return list(element);
if(tag==='PRE')return fence(element);
if(tag==='BLOCKQUOTE'){var quoted=container(element);return quoted?quoted.split('\n').map(function(line){return '> '+line;}).join('\n'):'';}
if(tag==='TABLE')return table(element);
if(tag==='HR')return '---';
return container(element);}
function fence(element){
var code=element.querySelector('code'),text=(code||element).textContent.replace(/\n$/,'');
if(!text.trim())return '';
var match=((code&&code.className)||element.className||'').match(/(?:language|lang)-([\w+#-]+)/);
var ticks=text.indexOf('```')>=0?'````':'```';
return ticks+(match?match[1]:'')+'\n'+text+'\n'+ticks;}
function list(element){
var ordered=element.tagName.toUpperCase()==='OL',index=parseInt(element.getAttribute('start')||'1',10),lines=[],pad=ordered?'   ':'  ';
element.childNodes.forEach(function(item){
if(item.nodeType!==1||item.tagName.toUpperCase()!=='LI'||hidden(item))return;
var text='',nested=[];
item.childNodes.forEach(function(child){
if(child.nodeType===1&&/^(UL|OL)$/i.test(child.tagName)){if(!hidden(child))nested.push(list(child));}
else if(child.nodeType===1&&blocks[child.tagName.toUpperCase()]&&!hidden(child))text+=' '+inline(child);
else text+=inlineNode(child);});
var line=(ordered?(index++)+'. ':'- ')+text.replace(/\s+/g,' ').trim();
lines.push(line);
nested.forEach(function(sub){sub.split('\n').forEach(function(subLine){lines.push(pad+subLine);});});});
return lines.join('\n');}
function table(element){
var rows=Array.prototype.filter.call(element.rows,function(row){return !hidden(row);});
if(!rows.length)return '';
var simple=rows.every(function(row){return Array.prototype.every.call(row.cells,function(cell){return cell.colSpan===1&&cell.rowSpan===1&&!cell.querySelector('table');});});
var widths=rows.map(function(row){return row.cells.length;});
simple=simple&&widths.every(function(width){return width===widths[0]&&width>0;});
if(!simple)return rows.map(function(row){return Array.prototype.map.call(row.cells,function(cell){return inline(cell).replace(/\s+/g,' ').trim();}).filter(Boolean).join(' | ');}).filter(Boolean).join('\n\n');
var cells=rows.map(function(row){return Array.prototype.map.call(row.cells,function(cell){return inline(cell).replace(/\s+/g,' ').trim().replace(/\|/g,'\\|');});});
var divider=cells[0].map(function(){return '---';});
var lines=[cells[0]].concat([divider]).concat(cells.slice(1));
return lines.map(function(line){return '| '+line.join(' | ')+' |';}).join('\n');}
var root=document.querySelector('main,[role=main]')||document.querySelector('article')||document.body;
if(!root)return;
var title=document.title.replace(/\s+/g,' ').trim(),body=container(root);
var heading='# '+title;
if(body.indexOf(heading)===0)body=body.slice(heading.length).replace(/^\s+/,'');
var markdown=(title?heading+'\n\n':'')+location.href+'\n\n'+body;
signal(token+':pagetext:'+request+':'+markdown.replace(/\n{3,}/g,'\n\n').trim()+'\n');
})();"#;

pub fn script(token: &str, request: u64) -> String {
    page_reply::instantiate(PAGE_MARKDOWN_SCRIPT, token, request)
}

pub fn request(browser: &Browser, request: u64) {
    page_reply::run_in_main_frame(browser, &script(token(), request));
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn script_carries_the_token_and_request_and_leaves_no_placeholders() {
        let script = script("abc", 41);
        assert!(script.starts_with("(function(){"));
        assert!(script.contains("var token=\"abc\",request=41,"));
        assert!(script.contains("':pagetext:'"));
        assert!(!script.contains("__"));
    }

    #[test]
    fn script_prefers_main_content_and_strips_page_chrome() {
        let script = script("abc", 1);
        assert!(script.contains("document.querySelector('main,[role=main]')"));
        for skipped in ["NAV", "FOOTER", "ASIDE", "SCRIPT", "STYLE"] {
            assert!(
                script.contains(&format!("{skipped}:1")),
                "{skipped} is not skipped"
            );
        }
    }

    #[test]
    fn script_balances_brackets() {
        let script = script("abc", 1);
        for (open, close) in [('(', ')'), ('{', '}'), ('[', ']')] {
            let opened = script.matches(open).count();
            let closed = script.matches(close).count();
            assert_eq!(opened, closed, "unbalanced {open}{close}");
        }
    }
}
