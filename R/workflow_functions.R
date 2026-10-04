# Read the named R chunks without evaluating code or chunk options.
smart31_workflow_chunks <- function(stage) {
  lines <- readLines(file.path("workflows",paste0(stage,".Rmd")))
  chunks <- list()
  i <- 1L
  while (i <= length(lines)) {
    if (!grepl("^```\\{r ",lines[i])) { i <- i+1L; next }
    label <- sub("^```\\{r ([^,}]+).*","\\1",lines[i])
    if (label %in% names(chunks)) stop("Duplicate workflow chunk: ",label)
    end <- i+1L
    while(end <= length(lines) && trimws(lines[end])!="```") end <- end+1L
    if(end > length(lines)) stop("Unclosed workflow chunk: ",label)
    code <- if(end==i+1L) character() else lines[seq.int(i+1L,end-1L)]
    if(!any(nzchar(trimws(code)))) stop("Empty workflow chunk: ",label)
    chunks[[label]] <- code
    i <- end+1L
  }
  if(!length(chunks)) stop("No named R chunks found in workflow: ",stage)
  chunks
}

# Load definitions from the Rmd in source order, including captured base implementations.
# Input-loading, simulation and output-writing expressions are not evaluated.
smart31_workflow_functions <- function(stage, env=new.env(parent=globalenv()), before_chunk=NULL) {
  chunks <- smart31_workflow_chunks(stage)
  chunks <- chunks[setdiff(names(chunks),"bootstrap")]
  if (!is.null(before_chunk)) {
    boundary <- match(before_chunk,names(chunks))
    if (is.na(boundary)) stop("Unknown chunk boundary.")
    chunks <- chunks[seq_len(boundary-1L)]
  }
  expressions <- parse(text=unlist(chunks,use.names=FALSE))
  for (x in expressions) {
    if (!is.call(x) || !as.character(x[[1]])[1] %in% c("<-","=") || !is.symbol(x[[2]])) next
    rhs <- x[[3]]
    if (is.call(rhs) && identical(rhs[[1]],as.name("function"))) eval(x,env)
    else if (is.symbol(rhs) && exists(as.character(rhs),env,inherits=FALSE) && is.function(get(as.character(rhs),env))) eval(x,env)
    else if (is.atomic(rhs) || (is.call(rhs) && identical(rhs[[1]],as.name("new.env")))) eval(x,env)
  }
  env
}
