param(
    $nugetApiKey,
    [switch]$CommitLocalGit,
    [switch]$PushGit,
    [switch]$PublishNuget,
    $specificPackages
    )

# https://github.com/borisyankov/DefinitelyTyped.git

$nuget = (get-item ".\tools\NuGet.CommandLine.2.2.1\tools\NuGet.exe")
$packageIdFormat = "{0}.TypeScript.DefinitelyTyped"
$nuspecTemplate = get-item ".\PackageTemplate.nuspec"

function Get-MostRecentNugetSpec($nugetPackageId) {
    $feeedUrl= "http://packages.nuget.org/v1/FeedService.svc/Packages()?`$filter=Id%20eq%20'$nugetPackageId'&`$orderby=Version%20desc&`$top=1"
    $webClient = new-object System.Net.WebClient
    $feedResults = [xml]($webClient.DownloadString($feeedUrl))
    return $feedResults.feed.entry
}

function Get-Last-NuGet-Version($spec) {
    $spec.properties.version
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
    [System.String]::Join(".", $parts)
}

function Configure-NuSpec($spec, $packageId, $newVersion, $pakageName, $dependentPackages, $newCommitHash) {

    $metadata = $spec.package.metadata

    $metadata.id = $packageId
    $metadata.version = $newVersion
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

function Resolve-Dependencies($packageFolder, $dependentPackages) {

    $packageFolder = get-item $packageFolder

    

    function Resolve-SubDependencies($dependencyName){
        if($dependentPackages.ContainsKey($dependencyName)){ 
            return
        }

        $dependentPackages.Add($dependencyName, $dependencyName);

        $dependentFolder = get-item "$($packageFolder.Parent.FullName)\$dependencyName"
        if(!(test-path $dependentFolder)){
            throw "no dependency [$dependencyName] found in [$dependentFolder]"
        } else {
            Resolve-Dependencies $dependentFolder $dependentPackages
        }
    }

    (ls $packageFolder -Recurse -Include *.d.ts) | `
        cat | `
        where { $_ -match "//.*(reference\spath=('|`")../(?<package>.*)(/|\\)(.*)\.ts('|`"))" } | `
        %{ $matches.package } | ` # pull the named regex package name out
        ?{ $_ } | ` # filter out any blank lines
        ?{ $_ -ne $packageFolder } | `
        %{ Resolve-SubDependencies $_ }

}


function Create-Package($packagesAdded, $newCommitHash) {
    BEGIN {
    }
    PROCESS {
		$dir = $_

		$packageName = $dir.Name
		$packageId = $packageIdFormat -f $packageName

		$tsFiles = ls $dir -recurse -include *.d.ts

		if(!($tsFiles)) {
            return;
        } else {

            $mostRecentNuspec = (Get-MostRecentNugetSpec $packageId)

			$currentVersion = $mostRecentNuspec.properties.version
			$newVersion = Increment-Version $currentVersion
			$packageFolder = "$packageId.$newVersion"
			
			# Create the directory structure
			$deployDir = "$packageFolder\Content\Scripts\typings\$packageName"
			Create-Directory $deployDir
			$tsFiles | %{ cp $_ $deployDir}


            $dependentPackages = @{}
            Resolve-Dependencies $dir $dependentPackages
			
			# setup the nuspec file
			$currSpecFile = "$packageFolder\$packageId.nuspec"
			cp $nuspecTemplate $currSpecFile
			$nuspec = [xml](cat $currSpecFile)
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
		}
    }
    END {
	}
}

function Update-Submodules {

    # make sure the submodule is here and up to date.
    git submodule init
    git submodule update
    git submodule foreach git pull origin master

}

function Get-MostRecentSavedCommit {
    $file = cat LAST_PUBLISHED_COMMIT -ErrorAction SilentlyContinue

    # first-time run and the file won't exist - clear any errors for now
    $Error.Clear()

    return $file;
}

function Get-NewestCommitFromDefinetlyTyped($definetlyTypedFolder, $lastPublishedCommitReference) {

    Update-Submodules

    pushd $definetlyTypedFolder

    git pull origin master

        if($lastPublishedCommitReference) {
            # Figure out what project (folders) have changed since our last publish
            $projectsToUpdate = git diff --name-status $lastPublishedCommitReference origin/master | `
                Select @{Name="ChangeType";Expression={$_.Substring(0,1)}}, @{Name="File"; Expression={$_.Substring(2)}} | `
                %{ [System.IO.Path]::GetDirectoryName($_.File) -replace "(.*)\\(.*)", '$1' } | `
                where { ![string]::IsNullOrEmpty($_) } | ` 
                select -Unique
        }

        $newLastCommitPublished = (git rev-parse HEAD);

    popd

    return $newLastCommitPublished;
}


$lastPublishedCommitReference = Get-MostRecentSavedCommit

$newCommitHash = Get-NewestCommitFromDefinetlyTyped ".\Definitions" $lastPublishedCommitReference

# Find updated repositories


if($specificPackages) {
    $allPackageDirectories = ls .\Definitions\* -Directory | ?{ $specificPackages -contains $_.Name }
}
else {
    $allPackageDirectories = ls .\Definitions\* -Directory
}

# Clean the build directory
rm build -recurse -force -ErrorAction SilentlyContinue
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

    $packageDirectories | create-package $packagesUpdated $newCommitHash

popd

$newCommitHash > LAST_PUBLISHED_COMMIT

# only commit update if there were no errors.
if($Error.Count -eq 0) {

    if($CommitLocalGit) {
        git add Definitions
        git add LAST_PUBLISHED_COMMIT
        git commit -m "Published NuGet Packages`n`n  - $([string]::join([System.Environment]::NewLine + "  - ", $packagesUpdated))"
    }

    if($PushGit) {
        git push origin master
    }
}
else {
    "*****"
    "ERROR During Process:"
    $Error
}