
# https://github.com/borisyankov/DefinitelyTyped.git

$nuget = (get-item ".\tools\NuGet.CommandLine.2.2.1\tools\NuGet.exe")
$packageIdFormat = "{0}.TypeScript.DefinetlyTyped"
$nuspecTemplate = get-item ".\PackageTemplate.nuspec"

function Get-Last-NuGet-Version($nuGetPackageId) {
    $feeedUrl = "http://packages.nuget.org/v1/FeedService.svc/Packages()?`$filter=Id%20eq%20'$nuGetPackageId'"
    $webClient = new-object System.Net.WebClient
    $queryResults = [xml]($webClient.DownloadString($feeedUrl))
    $queryResults.feed.entry | %{ $_.properties.version } | sort-object | select -last 1
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


function Create-Package() {
    BEGIN {
    }
    PROCESS {
		$dir = $_
		$packageName = $dir.Name
		$packageId = $packageIdFormat -f $packageName

		$tsFiles = ls $dir -recurse -include *.d.ts

		if( $tsFiles ) {
		
			$currentVersion = (Get-Last-NuGet-Version $packageId)
			$newVersion = Increment-Version $currentVersion
			$packageFolder = "$packageId.$newVersion"
			
			# Create the directory structure
			$deployDir = "$packageFolder\Content\Scripts\d.ts\$packageName"
			Create-Directory $deployDir
			$tsFiles | %{ cp $_ $deployDir}
			
			# setup the nuspec file
			$currSpecFile = "$packageFolder\$packageId.nuspec"
			cp $nuspecTemplate $currSpecFile
			$nuspec = [xml](cat $currSpecFile)
			$nuspec.package.metadata.id = $packageId
			$nuspec.package.metadata.version = $newVersion
			$nuspec.package.metadata.tags = "TypeScript JavaScript $pakageName"
			$nuspec.package.metadata.description = "TypeScript Definitions (d.ts) for {0} generated from the DefinetlyTyped github repository" -f $packageName
			$nuspec.Save((get-item $currSpecFile))

			& $nuget pack $currSpecFile
		}
    }
    END {
	}
}

$packageDirectories = ls .\Definitions\* -Directory

rm build -recurse -force -ErrorAction SilentlyContinue
Create-Directory build

try {
	pushd build

# for testing purposed - limits the number of packages created
#	$packageDirectories | select -first 5 | create-package
	$packageDirectories | create-package
	
	popd
}
catch {
	popd
	write-error $_
}