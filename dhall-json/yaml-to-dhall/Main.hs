{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE RecordWildCards     #-}
{-# LANGUAGE PatternGuards       #-}
{-# LANGUAGE FlexibleContexts    #-}
{-# LANGUAGE FlexibleInstances   #-}
{-# LANGUAGE LambdaCase          #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Main where

import qualified Control.Exception
import           Control.Exception (Exception, SomeException, throwIO)
import           Control.Monad (when)
import qualified Data.Aeson as A
import qualified Data.ByteString.Char8 as BS8
import qualified Data.ByteString.Lazy.Char8 as BSL8
import           Data.Monoid ((<>))
import           Data.Text (Text)
import qualified Data.Text.IO as Text
import           Data.Version (showVersion)
import qualified Data.Yaml as Y
import qualified GHC.IO.Encoding
import qualified Options.Applicative as O
import           Options.Applicative (Parser, ParserInfo)
import qualified System.Exit
import qualified System.IO

import qualified Dhall.Core as D
import           Dhall.JSONToDhall

import qualified Paths_dhall_json as Meta

-- ---------------
-- Command options
-- ---------------

-- | Command info and description
parserInfo :: ParserInfo Options
parserInfo = O.info
          (  O.helper <*> parseOptions)
          (  O.fullDesc
          <> O.progDesc "Populate Dhall value given its Dhall type (schema) from a YAML expression"
          )

-- | All the command arguments and options
data Options = Options
    { version    :: Bool
    , schema     :: Text
    , conversion :: Conversion
    } deriving Show

-- | Parser for all the command arguments and options
parseOptions :: Parser Options
parseOptions = Options <$> parseVersion
                       <*> parseSchema
                       <*> parseConversion
  where
    parseSchema  =  O.strArgument
                 (  O.metavar "SCHEMA"
                 <> O.help "Dhall type expression (schema)"
                 )
    parseVersion =  O.switch
                 (  O.long "version"
                 <> O.short 'V'
                 <> O.help "Display version"
                 )

-- ----------
-- YAML
-- ----------

showYAML :: A.Value -> String
showYAML value = BS8.unpack (Y.encode value)

data YAMLCompileError = YAMLCompileError CompileError

instance Show YAMLCompileError where
    show (YAMLCompileError e) = showCompileError "YAML" showYAML e

instance Exception YAMLCompileError

-- ----------
-- Main
-- ----------

main :: IO ()
main = do
    GHC.IO.Encoding.setLocaleEncoding GHC.IO.Encoding.utf8

    Options {..} <- O.execParser parserInfo

    when version $ do
      putStrLn (showVersion Meta.version)
      System.Exit.exitSuccess

    handle $ do
        stdin <- BSL8.getContents

        value :: A.Value <- case Y.decodeEither' . BS8.concat $ BSL8.toChunks stdin of
          Left err -> throwIO (userError $ Y.prettyPrintParseException err)
          Right v -> pure v

        expr <- typeCheckSchemaExpr YAMLCompileError =<< resolveSchemaExpr schema

        case dhallFromJSON conversion expr value of
          Left err -> throwIO $ YAMLCompileError err
          Right res -> Text.putStr (D.pretty res)

handle :: IO a -> IO a
handle = Control.Exception.handle handler
  where
    handler :: SomeException -> IO a
    handler e = do
        System.IO.hPutStrLn System.IO.stderr ""
        System.IO.hPrint    System.IO.stderr e
        System.Exit.exitFailure
