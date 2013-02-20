
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


function Create-Package($packagesAdded) {
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
			
			# setup the nuspec file
			$currSpecFile = "$packageFolder\$packageId.nuspec"
			cp $nuspecTemplate $currSpecFile
			$nuspec = [xml](cat $currSpecFile)
			$nuspec.package.metadata.id = $packageId
			$nuspec.package.metadata.version = $newVersion
			$nuspec.package.metadata.tags = "TypeScript JavaScript $pakageName"
			$nuspec.package.metadata.description = "TypeScript Definitions (d.ts) for {0} generated from the DefinitelyTyped github repository" -f $packageName
			$nuspec.Save((get-item $currSpecFile))

			& $nuget pack $currSpecFile
            $packagesAdded.add($packageId);
		}
    }
    END {
	}
}

# make sure the submodule is here and up to date.
git submodule init
git submodule update
git submodule foreach git pull origin master

# Find updated repositories

if(test-path LAST_PUBLISHED_COMMIT) {
    $lastPublishedCommitReference = cat LAST_PUBLISHED_COMMIT
} else {
    $lastPublishedCommitReference = $null
}

pushd Definitions

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


$allPackageDirectories = ls .\Definitions\* -Directory

rm build -recurse -force -ErrorAction SilentlyContinue
Create-Directory build

try {
	pushd build

    $packagesUpdated = New-Object Collections.Generic.List[string]

    # Filter out already published packages if we already have a LAST_PUBLISHED_COMMIT
    if($lastPublishedCommitReference -ne $null) {
        $packageDirectories = $allPackageDirectories | where { ($lastPublishedCommitReference -ne $null) -and $projectsToUpdate -contains $_.Name }
    }
    else {
        # first-time run. let's run all the packages.
        $packageDirectories = $allPackageDirectories
    }

    $packageDirectories | create-package $packagesUpdated

	popd

    $newLastCommitPublished > LAST_PUBLISHED_COMMIT

# No balls yet...
#    git add LAST_PUBLISHED_COMMIT
#    git commit -m "Published NuGet Packages`n`n  - $([string]::join([System.Environment]::NewLine + "  - ", $packagesUpdated))"
#    git push origin master
}
catch {
	popd
	write-error $_
}