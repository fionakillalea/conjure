import fs = require('fs');

interface InitFiles {
    db : string;
    eprime : string;
    minion : string;
}

function makeMessage(extension: string, count: number): string {
    return "Expected 1 " + extension + " file, got: " + count;  
}

export function findFiles(path: string): InitFiles {

    let files = fs.readdirSync(path);

    let eprimeFiles = files.filter(el => /\.eprime$/.test(el));

    if (eprimeFiles.length !== 1) {
        throw new Error(makeMessage("eprime", eprimeFiles.length));
    }

    let dbFiles = files.filter(el => /\.db$/.test(el));

    if (dbFiles.length !== 1) {
        throw new Error(makeMessage("db", dbFiles.length));
    }

    let minionFiles = files.filter(el => /\.eprime-minion$/.test(el));

    if (minionFiles.length !== 1) {
        throw new Error(makeMessage("minion", minionFiles.length));
    }

    return {db: path + "/" + dbFiles[0], eprime: path + "/" + eprimeFiles[0], minion: path + "/" + minionFiles[0]};
}

export function parseEprime(path: string){
    let eprime = fs.readFileSync(path).toString();
    let conjures = (eprime.split("Conjure's")[1]);

    let clean = conjures.replace(/\$/g, '');
    let json = JSON.parse(clean);
    let representations = json.representations;

    representations.forEach((rep: any) => {
        if (!("Name" in rep)){
            return;
        }

        
        console.log(rep);
    });


}