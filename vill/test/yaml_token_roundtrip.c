/* yaml_token_roundtrip.c */
/* Verify that the yaml_token() function is accurate by */
/* constructing a yaml file from its returned tokens, and comparing */
/* that with the original yaml input that was generated by 'viv'. */
#include <assert.h>            /* assert */
#include <stdio.h>             /* FILE pclose popen */
#include <stdlib.h>            /* abort free malloc */
#include <unistd.h>            /* getcwd */
#include "../src/yaml_token.h"  /* yaml_token */

/* show where to find the 'viv' Perl 6 parser */
#define VIV_RELATIVE_PATH ".."

#define USAGE "\nUsage: %s [options] [programfile]\n" \
  " -e cmd  execute cmd instead of programfile (multiple -e possible)\n" \
  " -h      show this help\n" \
  "\n"

const char * temp_filename1 = "/tmp/yaml_token_roundtrip1.yaml";
const char * temp_filename2 = "/tmp/yaml_token_roundtrip2.yaml";
#define BUFFER_SIZE 256
char   line_buffer[BUFFER_SIZE];
char * commandline;

/* Use the standard getopt() to find -e commands */
int
local_options( int argc, char * argv[] ) {
  int opt;
  commandline = malloc(1);
  strcpy( commandline, "" );
  while ((opt = getopt(argc, argv, "e:h")) != -1) {
    switch (opt) {
      case 'e':
        commandline = (char *) realloc( commandline,
          strlen(commandline) + strlen(optarg) + 1 );
        strcat( commandline, optarg );
        break;
      case 'h':
        fprintf( stderr, USAGE, argv[0] );
        exit(EXIT_SUCCESS);
        break;
      default: /* react to invalid options with help */
        fprintf( stderr, USAGE, argv[0] );
        exit(EXIT_FAILURE);
    }
  }
  return optind;
}

/* Round trip test the yaml_token function by converting the */
/* tokens a back to a YAML serialization stream. */
/* This should always match the original input document exactly. */
void
yaml_token_roundtrip( FILE * stream, FILE * outfile ) {
  enum yaml_token_type token_type;
  while ( outfile, (token_type=yaml_token(stream)) != YAML_TOKEN_FILE_END ) {
    fprintf( outfile, "%*s", yaml_token_data.spaces, "" );
    switch ( token_type ) {
      case YAML_TOKEN_LINE_END:
        fprintf( outfile, "\n" );
        break;
      case YAML_TOKEN_QUOTED:
        fprintf( outfile, "'%.*s'", (int)yaml_token_data.len, yaml_token_data.str );
        break;
      case YAML_TOKEN_BARE:
        fprintf( outfile, "%.*s%s", (int)yaml_token_data.len, yaml_token_data.str,
          yaml_token_data.colon_suffixed ? ":" : "" );
        break;
      default:
        fprintf( outfile, "UNKNOWN TOKEN\n" );
        abort();
        break;
    }
  }
}

/* run viv (a Perl 5 program) as a child process and save the output */
int
local_run_viv( char * viv_command, const char * output_filename ) {
  int status;
  char * cwd;
  FILE * infile, * outfile;
  /* stash the current working directory, then chdir to viv's dir */
  cwd = getcwd( NULL, 0);
  assert( cwd != NULL );
  char * stash_current_dir;
  stash_current_dir=(char *)malloc(strlen(cwd)+1);
  assert( stash_current_dir != NULL );
  strcpy( stash_current_dir, cwd );
  assert( chdir( VIV_RELATIVE_PATH ) == 0 );
  /* run viv in its own directory, letting the yaml parser pull lines */
  infile = popen( viv_command, "r" );
  assert( infile != NULL );
  /* stream the viv output to a first temporary file */
  outfile = fopen( output_filename, "w" );
  assert( outfile != NULL );
  while ( fgets(line_buffer, BUFFER_SIZE, infile) != NULL ) {
    fputs( (const char *)line_buffer, outfile );
  }
  fclose( outfile );
  status = pclose( infile ); /* non zero if viv had a fatal error */
  /* unfortunately the status is zero if viv has non fatal errors */
  assert( chdir( stash_current_dir ) == 0 );
  free( stash_current_dir );
  return status;
}

/* run the diff utility to compare two files */
int
local_run_diff( const char * filename1, const char * filename2 ) {
  int status;
  const char * diff_template = "diff %s %s";
  char * diff_command = (char *) malloc( strlen(diff_template) +
    strlen(filename1) + strlen(filename2) );
  assert( diff_command != NULL );
  sprintf( diff_command, diff_template, filename1, filename2 );
  status = system( diff_command );
  free( diff_command );
  return status;
}

int
local_test_commandline( char * commandline ) {
  int status = 0;
  FILE * infile, * outfile;
  printf( "yaml_token_roundtrip -e %s%.*s", commandline,
    49 - (int)strlen(commandline),
    "................................................." );
  char * viv_command;
  viv_command = malloc( 12 + strlen(commandline) );
  sprintf( viv_command, "./viv -e '%s'", commandline );
  status = local_run_viv( viv_command, temp_filename1 );
  free( viv_command );
  if ( status == 0 ) { /* test more only if viv returned success */
    infile = fopen( temp_filename1, "r" );
    assert( infile != NULL );
    outfile = fopen( temp_filename2, "w");
    assert( outfile != NULL );
    /* convert tokens back to original yaml doc */
    yaml_token_roundtrip( infile, outfile ); /* TODO: return status */
    fclose( infile );
    fclose( outfile );
    status = local_run_diff( temp_filename1, temp_filename2 );
  }
  printf( "%s\n", (status==0) ? "ok" : "not ok" );
  return status;
}

/* Generate a YAML file using viv, tokenize and reconstruct the YAML, */
/* compare the reconstruction with the original. */
int
local_test_one_file( char * programfile ) {
  int status;
  FILE * infile, * outfile;
  printf( "yaml_token_roundtrip %s%.*s", programfile,
    52 - (int)strlen(programfile),
    "...................................................." );
  char * viv_command;
  viv_command = malloc( 7 + strlen(programfile) );
  sprintf( viv_command, "./viv %s", programfile );
  status = local_run_viv( viv_command, temp_filename1 );
  if ( status == 0 ) { /* test more only if viv returned success */
    infile = fopen( temp_filename1, "r" );
    assert( infile != NULL );
    outfile = fopen( temp_filename2, "w");
    assert( outfile != NULL );
    /* convert tokens back to original yaml doc */
    yaml_token_roundtrip( infile, outfile ); /* TODO: return status */
    fclose( infile );
    fclose( outfile );
    status = local_run_diff( temp_filename1, temp_filename2 );
  }
  printf( "%s\n", (status==0) ? "ok" : "not ok" );
  return status;
}

/* dispatch tests according to the command line arguments */
int
main( int argc, char *argv[] ) {
  int optind, option, status, pass=0, fail=0;
  optind = local_options( argc, argv );
  if ( strlen(commandline) > 0 ) {
    status = local_test_commandline( commandline );
  }
  else {
    for ( option = optind; option < argc; option++ ) {
      status = local_test_one_file( argv[option] );
      if ( status ) { ++fail; }
      else          { ++pass; }
    }
    if ( argc > 2 ) {
      printf( "totals %d/%d pass %d fail\n", pass, argc - 1, fail );
    }
  }
  return 0;
}
