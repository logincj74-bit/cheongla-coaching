import { readFile, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const path=resolve(root,'ios/App/App/Info.plist');
let plist;
try{plist=await readFile(path,'utf8');}catch(error){if(error.code==='ENOENT'){console.log('iOS 생성 후 사진 권한 설명을 적용합니다.');process.exit(0);}throw error;}
const purposes={
  NSCameraUsageDescription:'질문에 문제 사진을 첨부하기 위해 카메라를 사용합니다.',
  NSPhotoLibraryUsageDescription:'질문에 첨부할 문제 사진을 선택하기 위해 사진 보관함을 사용합니다.',
  NSPhotoLibraryAddUsageDescription:'사용자가 요청한 문제 사진을 사진 보관함에 저장하기 위해 사용합니다.'
};
for(const [key,text] of Object.entries(purposes)){
  if(!plist.includes(`<key>${key}</key>`))plist=plist.replace(/<\/dict>\s*<\/plist>\s*$/,`\t<key>${key}</key>\n\t<string>${text}</string>\n</dict>\n</plist>\n`);
}
await writeFile(path,plist);
console.log('iOS 문제 사진 권한 설명 설정 완료');
