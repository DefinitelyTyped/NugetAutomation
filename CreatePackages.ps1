param(
    $nugetApiKey,
    [switch]$CommitLocalGit,
    [switch]$PushGit,
    [switch]$PublishNuget,
    [switch]$IsTeamCity,
    $specificPackages
    )

# https://github.com/borisyankov/DefinitelyTyped.git

$nuget = (get-item ".\tools\NuGet.CommandLine.2.2.1\tools\NuGet.exe")
$packageIdFormat = "{0}.TypeScript.DefinitelyTyped"
$nuspecTemplate = get-item ".\PackageTemplate.nuspec"

$packageToIgnoreBecauseSomeoneStoleTheNugetIdBOOOO = @(
    "Sjcl",     # https://www.nuget.org/packages/Sjcl.TypeScript.DefinitelyTyped/ 
    "Jsbn",     # https://www.nuget.org/packages/Jsbn.TypeScript.DefinitelyTyped/
    "BigInt",   # https://www.nuget.org/packages/BigInt.TypeScript.DefinitelyTyped/
    "TGrid"     # https://www.nuget.org/packages/TGrid.TypeScript.DefinitelyTyped/
    "React"     # https://www.nuget.org/packages/React.TypeScript.DefinitelyTyped/
)

# Store git credentials so we can push from AppVeyor
git config --global credential.helper store
Add-Content "$env:USERPROFILE\.git-credentials" "https://$($env:access_token):x-oauth-basic@github.com`n"
git checkout -q master

function Get-MostRecentNugetSpec($nugetPackageId) {
    $feeedUrl= "http://packages.nuget.org/v1/FeedService.svc/Packages()?`$filter=Id%20eq%20'$nugetPackageId'&`$orderby=Version%20desc&`$top=1"
    $webClient = new-object System.Net.WebClient
    $feedResults = [xml]($webClient.DownloadString($feeedUrl))
    return $feedResults.feed.entry
}

function Get-Last-NuGet-Version($spec) {
    $v = $spec.properties.version."#text"
    if(!$v) {
        $v = $spec.properties.version
    }
    $v
}

function Create-Directory($name){
    if(!(test-path $name)){
        mkdir $name | out-null
        write-host "Created Dir: $name"
    }
}


function Increment-Version($version){

    if(!$version) {
        return "0.0.1";
    }

    $parts = $version.split('.')
    for($i = $parts.length-1; $i -ge 0; $i--){
        $x = ([int]$parts[$i]) + 1
        if($i -ne 0) {
            # Don't roll the previous minor or ref past 10
            if($x -eq 10) {
                $parts[$i] = "0"
                continue
            }
        }
        $parts[$i] = $x.ToString()
        break;
    }
    $newVersion = [System.String]::Join(".", $parts)
    if($newVersion) {
        $newVersion
    } else {
        "0.0.1"
    }
}

function Configure-NuSpec($spec, $packageId, $newVersion, $pakageName, $dependentPackages, $newCommitHash) {

    $metadata = $spec.package.metadata

    $metadata.id = $packageId
    $metadata.version = [string]"$newVersion"
    $metadata.tags = "TypeScript JavaScript $pakageName"
    $metadata.description = "TypeScript Definitions (d.ts) for {0}. Generated based off the DefinitelyTyped repository [git commit: {1}]. http://github.com/DefinitelyTyped" -f $packageName, $newCommitHash

    if($dependentPackages) {

        #TODO: there may be a more concise way to work with this xml than doing string manipulation.
        $dependenciesXml = ""

        foreach($key in $dependentPackages.Keys) {
            $dependentPackageName = $packageIdFormat -f $key
            $dependenciesXml = $dependenciesXml + "<dependency id=`"$dependentPackageName`" />"
        }

        $metadata["dependencies"].InnerXml = $dependenciesXml
    }
}

function Resolve-Dependencies($packageFolder, $dependentPackages, $packageName) {

    $packageFolder = get-item $packageFolder



    function Resolve-SubDependencies($dependencyName){
        if($dependentPackages.ContainsKey($dependencyName)){
            # Try to guard against recursive dependencies
            return
        }

        if($dependencyName -eq $packageName) {
            # Don't include itself as a dependency
            return;
        }
        echo "dependencyName: $dependencyName  packageName: $packageName"

        $dependentPackages.Add($dependencyName, $dependencyName);

        $dependentFolder = get-item "$($packageFolder.Parent.FullName)\$dependencyName"
        if(!$dependentFolder -or !(test-path $dependentFolder)){
            throw "no dependency [$dependencyName] found in [$dependentFolder]"
        } else {
            Resolve-Dependencies $dependentFolder $dependentPackages $packageName
        }
    }

    (ls $packageFolder -Recurse -Include *.d.ts) | Where-Object {$_.FullName -notMatch "legacy"} | `
        cat | `
        where { $_ -match "//.*(reference\spath=('|`")../(?<package>.*)(/|\\)(.*)\.ts('|`"))" } | `
        %{ $matches.package } | `
        ?{ $_ } | `
        ?{ $_ -ne $packageFolder } | `
        %{ $_.TrimStart("../") } | `    # Not sure why, but the dx.devexpress package started creating an error that would return a package with '../jquery' from the above. (maybe a bad regex?). This is an ugly stop-gap for now.
        %{ Resolve-SubDependencies $_ }

}


function Create-Package($packagesAdded, $newCommitHash) {
    BEGIN {
    }
    PROCESS {
        $dir = $_

        $packageName = $dir.Name
        $packageId = $packageIdFormat -f $packageName

        $tsFiles = ls $dir -recurse -include *.d.ts | Where-Object {$_.FullName -notMatch "legacy"}

        if(!($tsFiles)) {
            return;
        } else {

            if($IsTeamCity) {
              "##teamcity[testStarted name='$packageId']"
            }

            try {

                $mostRecentNuspec = (Get-MostRecentNugetSpec $packageId)

                $currentVersion = Get-Last-NuGet-Version $mostRecentNuspec
                $newVersion = Increment-Version $currentVersion
                $packageFolder = "$packageId.$newVersion"

                # Create the directory structure
                $deployDir = "$packageFolder\Content\Scripts\typings\$packageName"
                Create-Directory $deployDir
                foreach($file in $tsFiles) {
                    $destFile = $deployDir + $file.FullName.Replace($dir, "")
                    mkdir (Split-Path $destFile) -Force | Out-Null
                    cp $file $destFile
                }


                $dependentPackages = @{}
                Resolve-Dependencies $dir $dependentPackages $packageName

                # setup the nuspec file
                $currSpecFile = "$packageFolder\$packageId.nuspec"
                cp $nuspecTemplate $currSpecFile
                $nuspec = [xml](cat $currSpecFile)
                "Configuring Nuspec newVersion:$newVersion"
                Configure-NuSpec $nuspec $packageId $newVersion $pakageName $dependentPackages $newCommitHash
                $nuspec.Save((get-item $currSpecFile))

                & $nuget pack $currSpecFile

                if($PublishNuget) {
                    if($nugetApiKey) {
                        & $nuget push "$packageFolder.nupkg" -ApiKey $nugetApiKey -NonInteractive
                    } else {
                        & $nuget push "$packageFolder.nupkg" -NonInteractive
                    }
                } else {
                    "***** - NOT publishing to Nuget - *****"
                }

                $packagesAdded.add($packageId);
            } catch {
              if($IsTeamCity) {
                  "##teamcity[message text='Error on package: $packageId' errorDetails='$_' status='ERROR']"
              } else {
                throw
              }
            }

        }
        if($IsTeamCity) {
            "##teamcity[testFinished name='$packageId']"
        }
    }
    END {
    }
}

function Update-Submodules {

    git submodule update --init --recursive -q

    # make sure the submodule is here and up to date.
    pushd .\Definitions
    git pull origin master -q
    popd
}

function Get-MostRecentSavedCommit {
    $file = cat LAST_PUBLISHED_COMMIT -ErrorAction SilentlyContinue

    # first-time run and the file won't exist - clear any errors for now
    $Error.Clear()

    return $file;
}

function Get-NewestCommitFromDefinetlyTyped($definetlyTypedFolder, $lastPublishedCommitReference, $projectsToUpdate) {

    Write-Host (Update-Submodules)

    pushd $definetlyTypedFolder

    git pull -q origin master | Out-Null

        if($lastPublishedCommitReference) {
            # Figure out what project (folders) have changed since our last publish
            git diff --name-status ($lastPublishedCommitReference).Trim() master | `
                Select @{Name="ChangeType";Expression={$_.Substring(0,1)}}, @{Name="File"; Expression={$_.Substring(2)}} | `
                %{ [System.IO.Path]::GetDirectoryName($_.File) -replace "(.*)\\(.*)", '$1' } | `
                where { ![string]::IsNullOrEmpty($_) } | `
                select -Unique | `
                where { !([string]$_).StartsWith("_") } | `
                %{ $projectsToUpdate.add($_); Write-host "found project to update: $_"; }
        }

        $newLastCommitPublished = (git rev-parse HEAD);

    popd

    return $newLastCommitPublished;
}


$lastPublishedCommitReference = Get-MostRecentSavedCommit

$projectsToUpdate = New-Object Collections.Generic.List[string]

# Find updated repositories
$newCommitHash = Get-NewestCommitFromDefinetlyTyped ".\Definitions" $lastPublishedCommitReference $projectsToUpdate

if(($newCommitHash | measure).count -ne 1) {
    "*****"
    $newCommitHash
    "*****"
    throw "commit hash not correct"
}

"*** Projects to update ***"
"**************************"
if($specificPackages) {
    $specificPackages
    $allPackageDirectories = ls .\Definitions\* | ?{ $_.PSIsContainer } | ?{ $specificPackages -contains $_.Name }
}
else {
    $projectsToUpdate
    $allPackageDirectories = ls .\Definitions\* | ?{ $_.PSIsContainer }
}

# Clean the build directory
if(test-path build) {
    rm build -recurse -force -ErrorAction SilentlyContinue
}
Create-Directory build

pushd build

    $packagesUpdated = New-Object Collections.Generic.List[string]

    # Filter out already published packages if we already have a LAST_PUBLISHED_COMMIT
    if($lastPublishedCommitReference -ne $null) {
        $packageDirectories = $allPackageDirectories | where { $projectsToUpdate -contains $_.Name }
    }
    else {
        # first-time run. let's run all the packages.
        $packageDirectories = $allPackageDirectories
    }

    if($IsTeamCity) {
    "##teamcity[testSuiteStarted name='DefinitlyTyped NugetAutomation']"
    }
    
    "*****"
    "`$packageDirectories - before filter"
    $packageDirectories
    "*****"

    # Some people for some reason claimed the NuGet id ending in this project's convention - arg
    # until we can work with NuGet team or package owner's to remove them we have to exclue them for now...
    $packageDirectories = $packageDirectories | where { $packageToIgnoreBecauseSomeoneStoleTheNugetIdBOOOO -notcontains $_ }

    "*****"
    "`$packageDirectories - after filter"
    $packageDirectories
    "*****"

    $packageDirectories | create-package $packagesUpdated $newCommitHash

    if($IsTeamCity) {
    "##teamcity[testSuiteFinished name='DefinitlyTyped NugetAutomation']"
    }
popd

$newCommitHash | out-file LAST_PUBLISHED_COMMIT -Encoding ascii


if($newCommitHash -eq $lastPublishedCommitReference) {
    "No new changes detected"
}
elseif($Error.Count -eq 0) {

    if($packagesUpdated.Count -gt 0)
    {
        $commitMessage =  "Published NuGet Packages`n`n  - $([string]::join([System.Environment]::NewLine + "  - ", $packagesUpdated))"
    } else {
        $commitMessage =  "No packages updated but something in the DefinitelyTyped submodule changed - upping the submodule commit"
    }

    "****"
    $commitMessage
    "****"

    if($CommitLocalGit) {
        git config user.name AppVeyor
        git config user.email jason@elegantcode.com
        git add Definitions
        git add LAST_PUBLISHED_COMMIT
        git commit -m $commitMessage
    }

    if($PushGit) {
        git remote add github https://github.com/DefinitelyTyped/NugetAutomation.git
        git push -q github master
        
        if ($LastExitCode -ne 0) {
            "git push exited with error"
            exit 1
        }
        "Pushed changes..."
    }
}
else {
    "*****"
    "ERROR During Process:"
    $Error
    exit 1
}
