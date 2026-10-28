const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const path=require('node:path'),base=path.join(__dirname,'..'),h=fs.readFileSync(path.join(base,'index.html'),'utf8'),p=fs.readFileSync(path.join(base,'print-tools.js'),'utf8'),catalog=JSON.parse(fs.readFileSync(path.join(base,'assets/mbti-study-methods.json'),'utf8'));
class N{constructor(tag){this.tag=tag;this.children=[];this.textContent='';}append(...nodes){this.children.push(...nodes);}}
const allText=n=>[n.textContent,...n.children.map(allText)].join('\n');let result;
const c=vm.createContext({open:(title,build,filename)=>{const body=new N('body');build(body,{createElement:tag=>new N(tag)});result={title,filename,body};return result;}});
vm.runInContext(h.slice(h.indexOf('const mbtiGroups='),h.indexOf('function canUseMBTIStudy(')),c);
vm.runInContext(p.slice(p.indexOf('function mbti('),p.indexOf('root.CheonglaPrint=')),c);
const groups=vm.runInContext('mbtiGroups',c);
for(const [code,guide]of Object.entries(catalog.types)){
 c.mbti(code,guide,groups);assert.equal(result.filename,'청라MBTI학습법_'+code);assert(result.title.includes(code));assert.equal(result.body.children.filter(x=>x.tag==='section').length,7);
 const output=allText(result.body);if(guide.subtitle)assert(output.includes(guide.subtitle));
 for(const item of [...guide.overview,...guide.coaching,...Object.values(guide.groupIntroductions||{})]){assert(output.includes(item.title));assert(output.includes(item.body));}
 for(const [key,body]of Object.entries(guide.subjects))assert(output.includes(body),code+' missing '+key);
 assert(!['button','input','select','details'].some(tag=>JSON.stringify(result.body).includes('"tag":"'+tag+'"')));
}
assert.throws(()=>c.mbti('',catalog.types.INTJ,groups));
console.log('PASS MBTI print: 16 types, all 7 groups, every overview/coaching/introduction/subject body, no collapsed content or form controls, type-specific filename');
