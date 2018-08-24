package ciTools
// This script is used in the Jenkins AWS Facade Jobs, with Active Choices Plugin (AC) parameters.
// AC parameters provide dynamic values, by running a Groovy script, that calls ciTools.AwsUI.callCmd("someName")
//  Tested with  Jenkins-v1.646, AC-v1.5.2, Scriptler-v2.9, 
//   Example use: 
//    You must have the install prefix of the groovy-ciTools folder added to CLASSPATH
//     1. Create  an AC parameter, Name: COMMAND, Groovy as follows:
//                new ciTools.AwsUI().callCmd("COMMAND")
//       Add to classpath the install prefix to ciTools
//     2. Create an AC Reactive Parameter, Name: SUBJECT, Reference: COMMAND, Groovy as follows:
//                new ciTools.AwsUI().callCmd("SUBJECT")
//       Add to classpath the install prefix to ciTools
//     3. Create an AC Reactive Reference Parameter, Name: Status, Choice Type: Fromatted HTML, Groovy as follows:
//                new ciTools.AwsUI().callCmd("showInst")
//       Add to classpath the install prefix to ciTools
//

// helloWorld test
//   Manually build the ciTools.jar: 
//      svn co https://svn.nps.edu/repos/metocgis/infrastructure/branches/rr_djones/tools/groovy
//      cd goovy
//      mkdir tmp.$$; groovyc -d target ciTools/AwsUI.groovy;  jar cvf ciTools.jar -C tmp.$$/ .
//      groovy -cp ciTools.jar -e 'new ciTools.AwsUI().helloWorld()'
def helloWorld() { println "ciTools.helloWorld" }

def getjiName() {
   try {
      return jenkinsProject.displayName 
    }
    catch ( e_val) {
       if ( System.env.CIDATA ) {
            return System.env.CIDATA.replaceAll( ~'^.*ciData/', "").replaceAll( ".json", "")
       } else {
            return  "ciStack"
       }
    } 
}


// Methods where the work is done
def updateCache() { 
    try { [ scm_tools, scm_cidata].each { updateWorkingCopy( sws, it) } }
    catch (e) { return ["ERROR: could not a update_workingCopy in $sws"] }
    listCacheFolders( )[0]
}
def updateWorkingCopy(folder, scm) {
  def leaf = scm.replaceFirst(~'.*/', "")
  println "update ${folder}/${leaf}"
  if (! (new File(folder)).exists()) (new File(folder)).mkdirs()
  if (! (new File(folder, leaf)).exists())  {
    def proc = "svn co ${scm}".execute( null, new File(folder))
    proc.text 
    // proc.exitValue()
  } else {
    def proc = "svn update".execute( null, new File("${folder}/${leaf}"))
    proc.text
    // proc.exitValue()
  }
}
// run the awsJobHelper, to populate the cache, and return a list of cache sub-directories, sorted by time.
def latestCachePath() { 
   def files = []
   (cache as File).eachFile groovy.io.FileType.DIRECTORIES, { files << it }
   "${cache}/" + files.sort{ a,b -> b.lastModified() <=> a.lastModified() }*.name[0]
}
   
def listCacheFolders() { 
  try {
   def files = []
   def proc = "${sws}/tools/awsJobHelper.sh  ${cidata()} ${cache}".execute()
   proc.text
   (cache as File).eachFile groovy.io.FileType.DIRECTORIES, { files << it }
   files.sort{ a,b -> b.lastModified() <=> a.lastModified() }*.name
  }
  catch( e_val ) {
    [ "ERROR: Could not list cache " + "ls -al $sws".execute().text ]
  }
}

def showInstHtml() {
   return (new File("${latestCachePath()}/showInst.html").text)
}
def showVolHtml() {
   return (new File("${latestCachePath()}/showVol.html").text)
}

def subjectChoices(command) { 
   p = new groovy.json.JsonSlurper()
   def json = p.parseText(new File( "${latestCachePath()}/instances.json").text)
   def data = p.parseText(new File( cidata() ).text)
   def l = json.Reservations.Instances.collect{ it }
   if  ( ["stop" ].contains(command) ) {
      return(l.findAll{ ! it.State.Name.contains("stopped")}.Tags.collect{ it[0].find{ 'Name' in it.Key }.Value }.sort())
   } else if   ( ["start" ].contains(command) ) {
      return(l.findAll{ ! it.State.Name.contains("running")}.Tags.collect{ it[0].find{ 'Name' in it.Key }.Value }.sort())
   } else if   ( ["launch" ].contains(command) ) {
       return(data.InstanceRoles.keySet().toList() )
   } else {
      return( l.Tags.collect{ it[0].find{ 'Name' in it.Key }.Value }.sort() )
   }
}

//return true if Jenkins administrator role
Boolean isAdminUser() {  
 ji  = jenkins.model.Jenkins.instance
 ji.getInstance().getACL().hasPermission(ji.ADMINISTER)
}
def instanceRoles(jsonPath) {
       def p = new groovy.json.JsonSlurper()
       def data = p.parseText(new File( jsonPath ).text)
       return(data.InstanceRoles.keySet().toList() )
}

// make it fixed to begin with, later, we need to add the vpc_{create/delete}, if this is admin
def commandChoices() { 
   def choices = []
   if ( cidata() == null ) return ( isAdminUser()  ? [ "create_ciData" ] : [ "ERROR:Admin required to create_ciData" ] )
  //  rl = [ ldapUser_update ]
  // if ( ! cidata()) return( rl << [ "create_cidata" ])
  // if ( ! instances()) {
  //    if ! vpcId() return( rl << [ "create_vpc" ])
  //    if  vpcId() return( rl << [ "delete_vpc" ])
  //} }
  [ "launch", "start", "stop", "terminate" ]
}

// test all the caller commnad-items
def test_rt( rt ) {
  rt.keySet().each { tryIt(rt, it) }
}
// helper function for testing 
def tryIt(rt, key ) { 
   try { println "test_tr: ${key}: ${rt[key]()}" } 
   catch(e) { println "rt[${key}]" + " Failed\n${e.message}\n::::\n" }
}

// This seems rather hacky, to write a method just to call a method, however in my novice understanding of Groovy, I have done this,
// becuase I need a way to set Class and package scoped variables or closures, like sws, cidata, and cache, 
// outside the top-level scripts that share this AwsUI package.
def callCmd( cmd ) {
   jobName = getjiName()
   // Set defaults if not in the binding. Jenkins job can override with a parameter of the same name.
   sws = binding.variables.SWS ?: "${System.getenv('HOME')}/sws"
   scmPrefix=binding.variables.SCM_PREFIX ?: "https://svn.nps.edu/repos/metocgis/infrastructure/trunk"
   scm_tools = binding.variables.SCM_TOOLS ?: "${scmPrefix}/tools"
   scm_cidata = binding.variables.SCM_CIDATA ?: "${scmPrefix}/ciData"
   cache = binding.variables.AWS_CACHE ?: "${sws}/.cache/${jobName}"
   //println "cache = ${cache}"
   // cidata is a closure, as the file may not yet exists, it should be evaluated just before use.
   cidata = { [ "${sws}/ciData/${jobName}.json", "${sws}/ciData/AWS_${jobName}.json" ].find{ new File(it).exists() } }
   //println "cidata = " +  cidata()
   // Map what to return, mostly to supply AC Parameter, by request.
   rt = [ showVariables: { binding.variables.keySet().toList() } ]
   rt << [ showVar: {binding.variables.collect{return it }.toList()} ]
   rt << [ SUBJECT:  { subjectChoices() } ]
   rt << [ COMMAND:  { commandChoices() } ]
   rt << [ showInst: { showInstHtml() } ]
   rt << [ showVol: { showVolHtml()} ]
   rt << [ cache: {[updateCache()]} ]
   rt << [ CACHE: {updateCache() ; [ listCacheFolders() ]} ]
   rt << [ SWS: {return [ sws ]} ]
   rt << [ CIDATA:  { [ cidata() ] } ]
   // 
   if  ( cmd == "test_rt" )   test_rt(rt) 
   // Should the Jenkins UI AC plugin use this w/o a valid cmd,  the returned result  should have the appearance of and ERROR
   // Bucause exception messages do not go back to the Jenkins UI, this scirpt should catches them.
   try { if (rt[cmd]) return( rt[cmd]() )} catch (e) { return ["ERROR: ${cmd}: ${e.message}"] }
   return [ "ERROR invalid: \"cmd=${cmd}\", Try one of the following:" ] + rt.keySet().toList()
}
